//
//  StateManagement.swift
//
//  Klaviyo Swift SDK
//
//  Created by Noah Durell on 12/6/22.
//
//  Description: This file contains the state management logic and actions for the Klaviyo Swift SDK.
//
//  Copyright (c) 2023 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

import AnyCodable
import Combine
import Foundation
import KlaviyoCore
import OSLog

enum StateManagementConstants {
    static let cellularFlushInterval = 30.0
    static let wifiFlushInterval = 10.0
    static let maxQueueSize = 200
    static let initialAttempt = 1
}

/// Describes how the state machine should handle retrying a request after a failure.
enum RetryState: Equatable {
    /// Indicates that the request should be retried immediately (subject to
    /// the regular flush cadence).
    ///
    /// - Parameter currentCount: The attempt number for the *current* request.
    ///   The value should start at `1` for the very first send and is incremented each
    ///   time a transient failure (such as a network error) occurs.
    case retry(_ currentCount: Int)

    /// Indicates that the request should be retried after waiting for a
    /// server-specified back-off interval. This path is typically triggered by
    /// an HTTP 429 "Too Many Requests" response that includes a `Retry-After`
    /// header.
    ///
    /// - Parameters:
    ///   - requestCount: The number of attempts made for this specific request.
    ///   - totalRetryCount: The total number of attempts made for this request across all retry strategies.
    ///   - currentBackoff: The remaining time in seconds to wait before the next retry attempt.
    case retryWithBackoff(requestCount: Int, totalRetryCount: Int, currentBackoff: Int)
}

enum KlaviyoAction: Equatable {
    /// Confirms or sets the API key, runs the legacy-state migration, drains the durable
    /// UnattributedBuffer into QueueStore, then emits `completeInitialization`.
    /// If already initialized, moves any existing push token to the new company's API key.
    case initialize(String)

    /// Hydrates identity and push-token from the canonical Core stores (IdentityStore)
    /// and starts the flush lifecycle.
    case completeInitialization(KlaviyoState)

    /// if initialized, set the email else queue it up
    case setEmail(String)

    /// if initialized set the phone number else queue it up
    case setPhoneNumber(String)

    /// if initialized set the external id else queue it up
    case setExternalId(String)

    /// call when a new push token needs to be set. If this token is the same we don't perform a network request to register the token
    case setPushToken(String, PushEnablement)

    /// Internal automatic-token path. Unlike the public/manual action, this may buffer the
    /// latest APNs token before SDK initialization has started.
    case setAutomaticPushToken(String, PushEnablement)

    /// call this to sync the user's local push notification authorization setting with the user's profile on the Klaviyo back-end.
    case setPushEnablement(PushEnablement)

    /// called when the user wants to reset the existing profile from state
    case resetProfile

    /// dequeues requests that completed and contuinues to flush other requests if they exist.
    case deQueueCompletedResults(KlaviyoRequest)

    /// when the network connectivity change we want to use a different flush interval to flush out the pending requests
    case networkConnectivityChanged(Reachability.NetworkStatus)

    /// flushes the queue say when the app is foregrounded or we come back to having network from not having
    case flushQueue

    /// picks up in flight requests and sends them out. handles errors and if no errors emits a `dequeCompletedResults`
    case sendRequest

    /// call when the app is backgrounded or terminated
    case stop

    /// call after initialization or when the app is foregrounded. This action will  flush the queue at some predefined intervals
    case start

    /// cancels any in flight requests. this can be called when there is no network or from `stop` when app is going to be backgrounded
    case cancelInFlightRequests

    /// called when there is a network or rate limit error
    case requestFailed(KlaviyoRequest, RetryState)

    /// when there is an event to be sent to klaviyo it's added to the queue
    case enqueueEvent(Event)

    /// when there is an aggregate event to be sent to klaviyo it's added to the queue
    case enqueueAggregateEvent(Data)

    /// when there is an profile to be sent to klaviyo it's added to the queue
    case enqueueProfile(Profile)

    /// when there is a subscription to be sent to klaviyo it's added to the queue
    case enqueueSubscription(Subscription)

    /// when setting individual profile props
    case setProfileProperty(Profile.ProfileKey, AnyEncodable)

    /// resets the state for profile properties before dequeing the request
    /// this is done in the case where there is http request failure due to
    /// the data that was passed to the client endpoint
    case resetStateAndDequeue(KlaviyoRequest, [InvalidField])

    /// when the host app receives a Klaviyo tracking link that should be resolved to a destination link.
    /// This action makes a call to an engtrack service that will return the destination link *and* log the click.
    case trackingLinkReceived(URL)

    /// when the attempt to resolve the tracking link into a destination link fails.
    /// This action will enqueue a request that, when delivered, will log the click via the engtrack service.
    case trackingLinkResolutionFailed(trackingLink: URL, clickTime: Date)
}

struct RequestId {}
struct FlushTimer {}

struct KlaviyoReducer: ReducerProtocol {
    typealias State = KlaviyoState
    typealias Action = KlaviyoAction

    func reduce(into state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> {
        // Write-through choke point: `apiKey` / `identity` / `pushTokenData` are canonical in the
        // KlaviyoCore stores; `KlaviyoState` holds an in-memory projection. Capture the projection
        // before the action runs and, on any mutation, write it back so identity/apiKey/pushToken
        // are persisted synchronously (the debounced state save is queue-only). `defer` fires on
        // every return path, so no mutation site can silently drop a write. Value-equality guards
        // avoid redundant emits (e.g. hydration reading its own value).
        let previousApiKey = state.apiKey
        let previousIdentity = state.identity
        let previousPushTokenData = state.pushTokenData
        defer {
            if state.apiKey != previousApiKey {
                SDKConfigStore.shared.update(KlaviyoConfig(apiKey: state.apiKey))
            }
            if state.identity != previousIdentity {
                IdentityStore.shared.update(state.identity)
            }
            if state.pushTokenData != previousPushTokenData {
                IdentityStore.shared.updatePushToken(state.pushTokenData)
            }
        }

        switch action {
        case let .initialize(apiKey):
            if case .initialized = state.initalizationState {
                guard apiKey != state.apiKey else {
                    return .none
                }
                // Since we are moving the token to a new company lets remove the token from the old company first.
                if let apiKey = state.apiKey,
                   let anonymousId = state.anonymousId,
                   let tokenData = state.pushTokenData {
                    let request = RequestFactory.unregisterRequest(
                        identity: state.requestIdentity(apiKey: apiKey, anonymousId: anonymousId),
                        pushToken: tokenData.pushToken
                    )
                    state.enqueueRequest(request: request)
                }
                state.apiKey = apiKey
                state.reset()
            } else if case .uninitialized = state.initalizationState,
                      let previousApiKey = SDKConfigStore.shared.current.apiKey,
                      previousApiKey != apiKey {
                // Cold-start company switch. Identity + push token are device-scoped in the Core
                // stores and still hold the PREVIOUS company's profile; the runtime branch above only
                // fires when already `.initialized`. Mirror it here so a fresh launch under a new
                // apiKey does not bleed prior PII into the new company or leave its push token
                // registered. Sourced from the stores (not `state`, which is empty on cold start).
                let previous = IdentityStore.shared.current
                if let anonymousId = previous.anonymousId, let tokenData = IdentityStore.shared.pushToken {
                    let request = RequestFactory.unregisterRequest(
                        identity: RequestIdentity(
                            apiKey: previousApiKey,
                            anonymousId: anonymousId,
                            email: previous.email,
                            phoneNumber: previous.phoneNumber,
                            externalId: previous.externalId
                        ),
                        pushToken: tokenData.pushToken
                    )
                    // Persist synchronously before the wipe below so the unregister survives a
                    // crash between cold-start company switch and the first flush.
                    QueueStore.store(for: previousApiKey).enqueue(request, persist: .synchronous)
                }
                IdentityStore.shared.updatePushToken(nil)
                if previous.email != nil || previous.phoneNumber != nil || previous.externalId != nil {
                    // Identified profile: mint a fresh anon and drop PII so `.completeInitialization`
                    // hydrates a clean identity for the new company.
                    IdentityStore.shared.update(ProfileData(anonymousId: IdentityStore.shared.mintNewAnonymousId()))
                }
            }
            guard case .uninitialized = state.initalizationState else {
                return .none
            }
            state.initalizationState = .initializing
            // Set the confirmed apiKey on the projection; the write-through `defer` is the sole
            // writer to `SDKConfigStore` (one persist + one emit per initialize). This triggers it.
            state.apiKey = apiKey
            return .run { send in
                // Must run before IdentityStore hydrates below.
                migrateLegacyStateIfNeeded(apiKey: apiKey)
                // Drain any request-generating calls buffered before an apiKey was known into the
                // now-resolvable QueueStore (at-least-once; the durable buffer is trimmed only after
                // the queue write persists). Runs after migration so a migrated queue is present.
                RequestEnqueuer.drainBuffer(apiKey: apiKey)
                // Identity/apiKey/pushToken are hydrated from the Core stores in
                // `.completeInitialization`; no disk load needed.
                await send(.completeInitialization(KlaviyoState(requestsInFlight: [])))
            }

        case var .completeInitialization(initialState):
            guard case .initializing = state.initalizationState else {
                return .none
            }
            // Hydrate identity + push token from the canonical Core stores. `anonymousId` is
            // guaranteed present (IdentityStore mints on first access). The apiKey was already
            // confirmed + written through in `.initialize`, so carry it over from `state` (the
            // loaded queue-only blob has no apiKey). Any identity fields set on the SDK-level
            // state before init completed are carried over on top.
            initialState.identity = IdentityStore.shared.current
            initialState.pushTokenData = IdentityStore.shared.pushToken
            initialState.apiKey = state.apiKey
            if let email = state.email {
                initialState.email = email
            }
            if let phoneNumber = state.phoneNumber {
                initialState.phoneNumber = phoneNumber
            }
            if let externalId = state.externalId {
                initialState.externalId = externalId
            }

            state = initialState
            state.initalizationState = .initialized

            // Any request-generating calls made before init were routed to the durable
            // `UnattributedBuffer` and already drained into the QueueStore by `.initialize`
            // (before this action fires), so there is nothing to replay here.
            return .run { send in
                await send(.start)
            }
            .merge(with: environment.lifecycleEventsWithReachability().map(\.transformToKlaviyoAction).eraseToEffect())

        case let .setEmail(email):
            guard case .initialized = state.initalizationState else {
                setPreInitIdentifier(&state) { $0.email = email.trimWhiteSpaceOrReturnNilIfEmpty() }
                return .none
            }
            state.updateEmail(email: email)
            return .none

        case let .setPhoneNumber(phoneNumber):
            guard case .initialized = state.initalizationState else {
                setPreInitIdentifier(&state) {
                    $0.phoneNumber = phoneNumber.trimWhiteSpaceOrReturnNilIfEmpty()
                }
                return .none
            }
            state.updatePhoneNumber(phoneNumber: phoneNumber)
            return .none

        case let .setExternalId(externalId):
            guard case .initialized = state.initalizationState else {
                setPreInitIdentifier(&state) { $0.externalId = externalId.trimWhiteSpaceOrReturnNilIfEmpty() }
                return .none
            }
            state.updateExternalId(externalId: externalId)
            return .none

        case let .setAutomaticPushToken(pushToken, enablement):
            // Forward to `setPushToken` in every state: post-init it builds + enqueues the token
            // request; pre-init `setPushToken` routes through the ungated `RequestEnqueuer` (durable
            // buffer) like a manual token. The old pre-init dedup into `pendingRequests` is dropped
            // with that machinery — repeated pre-init auto-token fires buffer idempotent duplicates.
            return .run { send in
                await send(.setPushToken(pushToken, enablement))
            }

        case let .setPushToken(pushToken, enablement):
            guard case .initialized = state.initalizationState,
                  let apiKey = state.apiKey,
                  let anonymousId = state.anonymousId
            else {
                RequestEnqueuer.enqueuePushToken(pushToken, enablement: enablement)
                return .none
            }
            if !state.shouldSendTokenUpdate(newToken: pushToken, enablement: enablement) {
                return .none
            }

            let request = state.resolvedTokenRequest(
                apiKey: apiKey,
                anonymousId: anonymousId,
                pushToken: pushToken,
                enablement: enablement
            )
            state.enqueueRequest(request: request)
            return .none

        case let .setPushEnablement(enablement):
            guard let pushToken = state.pushTokenData?.pushToken else {
                return .none
            }

            return .run { send in
                await send(KlaviyoAction.setPushToken(pushToken, enablement))
            }

        case .flushQueue:
            guard case .initialized = state.initalizationState else {
                return .none
            }
            if state.flushing {
                return .none
            }
            // The priority path can dispatch `.flushQueue` while offline, where `flushInterval` is
            // `.infinity` — the backoff below would trap on `Int()`, and draining is pointless.
            guard state.flushInterval.isFinite else {
                return .none
            }
            if case let .retryWithBackoff(requestCount, totalCount, backOff) = state.retryState {
                let newBackOff = max(backOff - Int(state.flushInterval), 0)
                if newBackOff > 0 {
                    state.retryState = .retryWithBackoff(
                        requestCount: requestCount,
                        totalRetryCount: totalCount,
                        currentBackoff: newBackOff
                    )
                    return .none
                } else {
                    state.retryState = .retry(requestCount)
                }
            }
            if state.pendingProfile != nil {
                state.enqueueProfileOrTokenRequest()
            }
            guard let apiKey = state.apiKey else {
                return .none
            }
            // Lease the durable pending queue into the in-memory in-flight set: `drainAll` atomically
            // snapshots + clears the store (parity with the former `append(contentsOf:)` +
            // `removeAll`). In-flight stays an in-memory reducer field.
            let batch = QueueStore.store(for: apiKey).drainAll()
            if batch.isEmpty {
                return .none
            }
            state.requestsInFlight.append(contentsOf: batch)
            state.flushing = true
            return .task {
                .sendRequest
            }

        case .stop:
            guard case .initialized = state.initalizationState else {
                return .none
            }
            return EffectPublisher.cancel(ids: [RequestId.self, FlushTimer.self])
                .concatenate(with: .run(operation: { send in
                    await send(.cancelInFlightRequests)
                    await MainActor.run { BadgeManager.syncBadgeCount() }
                }))

        case .start:
            guard case .initialized = state.initalizationState else {
                return .none
            }

            return .merge([
                .run { send in
                    let settings = await environment.getNotificationSettings()
                    await send(KlaviyoAction.setPushEnablement(settings))
                    let autoclearing = await environment.getBadgeAutoClearingSetting()
                    if autoclearing {
                        await BadgeManager.setBadgeCount(0)
                    } else {
                        await MainActor.run { BadgeManager.syncBadgeCount() }
                    }
                },
                environment.timer(state.flushInterval)
                    .map { _ in
                        KlaviyoAction.flushQueue
                    }
                    .eraseToEffect()
                    .cancellable(id: FlushTimer.self, cancelInFlight: true)
            ])

        case let .deQueueCompletedResults(completedRequest):
            if case let .registerPushToken(_, payload) = completedRequest.endpoint {
                let requestData = payload.data.attributes
                let enablement = PushEnablement(rawValue: requestData.enablementStatus) ?? .authorized
                let backgroundStatus = PushBackground(rawValue: requestData.backgroundStatus) ?? .available
                state.pushTokenData = PushTokenData(
                    pushToken: requestData.token,
                    pushEnablement: enablement,
                    pushBackground: backgroundStatus,
                    deviceData: requestData.deviceMetadata
                )
            }
            state.requestsInFlight.removeAll { inflightRequest in
                completedRequest.id == inflightRequest.id
            }
            state.retryState = RetryState.retry(StateManagementConstants.initialAttempt)
            if state.requestsInFlight.isEmpty {
                state.flushing = false
                return .none
            }
            return .task { .sendRequest }.cancellable(id: RequestId.self)

        case .sendRequest:
            guard case .initialized = state.initalizationState else {
                return .none
            }
            guard state.flushing else {
                return .none
            }

            guard let request = state.requestsInFlight.first else {
                state.flushing = false
                return .none
            }
            let retryState = state.retryState
            var numAttempts = 1
            if case let .retry(attempts) = retryState {
                numAttempts = attempts
            }

            return .run { [numAttempts] send in
                let requestAttemptInfo: RequestAttemptInfo
                do {
                    requestAttemptInfo = try RequestAttemptInfo(
                        attemptNumber: numAttempts,
                        maxAttempts: request.endpoint.maxRetries
                    )
                } catch {
                    environment.emitDeveloperWarning("Invalid RequestAttemptInfo parameters: \(error)")
                    await send(.cancelInFlightRequests)
                    return
                }

                let result = await environment.klaviyoAPI.send(request, requestAttemptInfo)
                switch result {
                case .success:
                    await send(.deQueueCompletedResults(request))
                case let .failure(error):
                    await send(handleRequestError(request: request, error: error, retryState: retryState))
                }
            } catch: { error, send in
                // For now assuming this is cancellation since nothing else can throw AFAICT
                environment.emitDeveloperWarning("Unknown error thrown during request processing \(error)")
                await send(.cancelInFlightRequests)
            }.cancellable(id: RequestId.self)

        case .cancelInFlightRequests:
            state.flushing = false
            // Restore the leased in-flight requests to the front of the durable pending queue.
            // `.synchronous`: the in-flight set is in-memory only and is cleared just below, so if
            // the process ends within a debounce window (this runs on `.stop`/background) the batch
            // would be lost from both memory and disk. Write it before returning.
            if let apiKey = state.apiKey, !state.requestsInFlight.isEmpty {
                QueueStore.store(for: apiKey).prepend(state.requestsInFlight, persist: .synchronous)
            }
            state.requestsInFlight = []
            return .none

        case let .networkConnectivityChanged(networkStatus):
            guard case .initialized = state.initalizationState else {
                return .none
            }
            switch networkStatus {
            case .notReachable:
                state.flushInterval = Double.infinity
                return EffectPublisher.cancel(ids: [RequestId.self, FlushTimer.self])
                    .concatenate(with: .run { send in
                        await send(.cancelInFlightRequests)
                    })
            case .reachableViaWiFi:
                state.flushInterval = StateManagementConstants.wifiFlushInterval
            case .reachableViaWWAN:
                state.flushInterval = StateManagementConstants.cellularFlushInterval
            }
            return environment.timer(state.flushInterval)
                .map { _ in
                    KlaviyoAction.flushQueue
                }.eraseToEffect()
                .cancellable(id: FlushTimer.self, cancelInFlight: true)

        case let .requestFailed(request, retryState):
            var exceededRetries = false
            switch retryState {
            case let .retry(count):
                exceededRetries = count > request.endpoint.maxRetries
                state.retryState = .retry(exceededRetries ? 1 : count)
            case let .retryWithBackoff(requestCount, totalCount, backOff):
                exceededRetries = requestCount > request.endpoint.maxRetries
                state.retryState = .retryWithBackoff(requestCount: exceededRetries ? 0 : requestCount, totalRetryCount: totalCount, currentBackoff: backOff)
            }
            if exceededRetries {
                state.requestsInFlight.removeAll { inflightRequest in
                    request.id == inflightRequest.id
                }
            }
            state.flushing = false
            // Restore the leased in-flight requests to the front of the durable pending queue.
            // `.synchronous`: the in-flight set is in-memory only and is cleared just below, so if
            // the process ends within a debounce window (this runs on `.stop`/background) the batch
            // would be lost from both memory and disk. Write it before returning.
            if let apiKey = state.apiKey, !state.requestsInFlight.isEmpty {
                QueueStore.store(for: apiKey).prepend(state.requestsInFlight, persist: .synchronous)
            }
            state.requestsInFlight = []
            return .none

        case var .enqueueEvent(event):
            guard case .initialized = state.initalizationState,
                  let apiKey = state.apiKey,
                  let anonymousId = state.anonymousId
            else {
                RequestEnqueuer.enqueueEvent(event)
                return .none
            }

            event = event.updateEventWithIdentifiers(
                email: state.email,
                phoneNumber: state.phoneNumber,
                externalId: state.externalId,
                pushToken: state.pushTokenData?.pushToken
            )

            let request = RequestFactory.eventRequest(
                identity: state.requestIdentity(apiKey: apiKey, anonymousId: anonymousId),
                event: event,
                pushToken: state.pushTokenData?.pushToken
            )

            /*
             High-priority requests (e.g. opened-push, geofence events) are front-inserted (inside
             `QueueStore.enqueue`, keyed on `request.priority`) and trigger an immediate flush so
             that user engagement events are not delayed. All other requests are appended and
             flushed on the regular intervals defined in `StateManagementConstants`.
             */
            let shouldPrioritize = request.priority == .high
            state.enqueueRequest(request: request)

            let baseEffect = shouldPrioritize ? EffectTask<KlaviyoAction>.task { .flushQueue } : .none
            return .merge([
                baseEffect,
                .fireAndForget { enrichAndPublishEvent(event) }
            ])

        case let .enqueueAggregateEvent(payload):
            guard case .initialized = state.initalizationState,
                  let apiKey = state.apiKey
            else {
                RequestEnqueuer.enqueueAggregateEvent(payload)
                return .none
            }

            let endpoint = KlaviyoEndpoint.aggregateEvent(apiKey, payload)
            let request = KlaviyoRequest(endpoint: endpoint)

            state.enqueueRequest(request: request)

            return .none

        case let .enqueueProfile(profile):
            guard case .initialized = state.initalizationState
            else {
                // Pre-init: mirror the initialized path against the canonical persisted identity.
                // Seed `state.identity` from `IdentityStore` so we fold onto (not clobber) the
                // stored profile, run the SAME identifier-change reset, then push synchronously
                // so the merged identity is durable before the profile sync is buffered.
                state.identity = IdentityStore.shared.current
                let preInitCurrentIds = [state.email, state.phoneNumber, state.externalId]
                let preInitIncomingIds = [profile.email, profile.phoneNumber, profile.externalId].map {
                    $0?.trimWhiteSpaceOrReturnNilIfEmpty()
                }
                // Identifier change on an already-identified profile → mint a fresh anonymousId and
                // drop prior PII, so a set(profile:) with different identifiers before initialize()
                // on a later launch does not reuse the previous user's anonymousId (which would
                // merge two people onto one profile). Mirrors the initialized branch below.
                if state.isIdentified, preInitCurrentIds != preInitIncomingIds {
                    state.reset(preserveTokenData: false)
                }
                state.updateStateWithProfile(profile: profile)
                IdentityStore.shared.update(state.identity)
                guard let anonymousId = state.anonymousId else { return .none }
                // Build the full payload exactly as the initialized path does, so structured
                // attributes (name/title/organization/image/location) survive the pre-init buffer
                // and sync completely after initialize() (MAGE-1141).
                let payload = CreateProfilePayload(data: ProfilePayload(
                    profile,
                    email: state.email,
                    phoneNumber: state.phoneNumber,
                    externalId: state.externalId,
                    anonymousId: anonymousId
                ))
                RequestEnqueuer.enqueueProfile(payload: payload)
                return .none
            }

            let pushTokenData = state.pushTokenData
            let currentIds = [state.email, state.phoneNumber, state.externalId]
            let incomingIds = [profile.email, profile.phoneNumber, profile.externalId].map {
                // Normalize with the same trimming used by updateStateWithProfile
                // so whitespace-padded inputs match their stored counterparts.
                $0?.trimWhiteSpaceOrReturnNilIfEmpty()
            }

            let identifiersChanged = currentIds != incomingIds

            // Only reset if the incoming profile has different identifiers.
            // Anonymous ID is the lowest-order identifier, so there's no reason
            // to regenerate it when higher-order identifiers haven't changed.
            // Resetting with the same identifiers causes unnecessary anonymous ID
            // churn, which triggers spurious push-token API requests.
            // resetProfile() remains available for explicitly clobbering all state.
            if state.isIdentified, identifiersChanged {
                state.reset(preserveTokenData: false)
            }
            state.updateStateWithProfile(profile: profile)

            // Skip the API call entirely when there is nothing new to sync:
            // identifiers are unchanged, the profile carries no extra attributes,
            // and no profile properties are queued up via setProfileProperty.
            if !identifiersChanged, !profile.hasNonIdentifierData, state.pendingProfile == nil {
                return .none
            }

            guard let anonymousId = state.anonymousId,
                  let apiKey = state.apiKey
            else {
                return .none
            }
            let profilePayload = ProfilePayload(
                profile,
                email: state.email,
                phoneNumber: state.phoneNumber,
                externalId: state.externalId,
                anonymousId: anonymousId
            )

            let request: KlaviyoRequest
            if let tokenData = pushTokenData {
                request = RequestFactory.tokenRequest(
                    apiKey: apiKey,
                    pushToken: tokenData.pushToken,
                    enablement: tokenData.pushEnablement,
                    background: tokenData.pushBackground.rawValue,
                    profile: profilePayload
                )
            } else {
                request = RequestFactory.profileRequest(
                    apiKey: apiKey,
                    payload: CreateProfilePayload(data: profilePayload)
                )
            }
            state.enqueueRequest(request: request)

            return .none

        case let .enqueueSubscription(subscription):
            guard case .initialized = state.initalizationState,
                  let apiKey = state.apiKey,
                  let anonymousId = state.anonymousId
            else {
                // Pre-init: mirror the initialized path against the canonical persisted identity, then
                // buffer the apiKey-free payload through the ungated `RequestEnqueuer` (apiKey stamped
                // at drain) so a subscribe issued before initialize() survives instead of being
                // dropped (MAGE-1136).
                state.identity = IdentityStore.shared.current
                guard let anonymousId = state.anonymousId,
                      let payload = state.buildSubscriptionPayload(
                          anonymousId: anonymousId, subscription: subscription
                      )
                else {
                    return .none
                }
                RequestEnqueuer.enqueueSubscription(payload: payload)
                return .none
            }

            guard let request = state.buildSubscriptionRequest(
                apiKey: apiKey,
                anonymousId: anonymousId,
                subscription: subscription
            ) else {
                return .none
            }
            state.enqueueRequest(request: request)

            return .none

        case .resetProfile:
            guard case .initialized = state.initalizationState
            else {
                return .none
            }
            state.reset()
            return .none

        case let .setProfileProperty(key, value):
            guard var pendingProfile = state.pendingProfile else {
                state.pendingProfile = [key: value]
                return .none
            }
            pendingProfile[key] = value
            state.pendingProfile = pendingProfile
            return .none

        case let .resetStateAndDequeue(request, invalidFields):
            for invalidField in invalidFields {
                switch invalidField {
                case .email:
                    state.email = nil
                case .phone:
                    state.phoneNumber = nil
                }
            }

            return .task { .deQueueCompletedResults(request) }

        case let .trackingLinkReceived(trackingLinkURL):
            // Thin entry point: the resolution work lives in `TrackingLinkManager`.
            // This case only remains in the reducer to read identity and (on
            // failure) enqueue; it will fold into the manager once identity and the
            // queue are canonical in KlaviyoCore. See `TrackingLinkManager`.
            let clickTime = environment.date()

            if #available(iOS 14.0, *) {
                Logger.stateLogger.info("Attempting to resolve tracking link destination from tracking URL '\(trackingLinkURL.absoluteString)'")
            }

            let profileInfo = ProfilePayload(
                email: state.email,
                phoneNumber: state.phoneNumber,
                externalId: state.externalId,
                anonymousId: state.anonymousId ?? ""
            )

            return .run { send in
                let outcome = await TrackingLinkManager.resolveDestination(
                    trackingLink: trackingLinkURL,
                    profileInfo: profileInfo
                )
                switch outcome {
                case let .resolved(destinationURL):
                    await DeepLinkManager.openDeepLink(destinationURL)
                case .failed:
                    await send(.trackingLinkResolutionFailed(trackingLink: trackingLinkURL, clickTime: clickTime))
                }
            }

        case let .trackingLinkResolutionFailed(trackingLink, clickTime):
            // Kept in the reducer only for the enqueue below (a state mutation).
            // Folds into `TrackingLinkManager` once the queue is canonical in
            // KlaviyoCore.
            guard case .initialized = state.initalizationState, state.apiKey != nil else {
                // Pre-init: route through the ungated `RequestEnqueuer` (identity resolved from the
                // canonical `IdentityStore`) so a click that fails resolution before initialize() is
                // parked in the durable buffer instead of dropped by the apiKey-gated
                // `state.enqueueRequest` (MAGE-1136).
                RequestEnqueuer.enqueueTrackingLinkClicked(trackingLink: trackingLink, clickTime: clickTime)
                return .none
            }
            let profileInfo = ProfilePayload(
                email: state.email,
                phoneNumber: state.phoneNumber,
                externalId: state.externalId,
                anonymousId: state.anonymousId ?? ""
            )

            let request = KlaviyoRequest(
                endpoint: .logTrackingLinkClicked(
                    trackingLink: trackingLink,
                    clickTime: clickTime,
                    profileInfo: profileInfo
                )
            )
            state.enqueueRequest(request: request)

            return .none
        }
    }

    /// Applies a pre-init identity-setter (`setEmail`/`setPhoneNumber`/`setExternalId`) and buffers
    /// a profile sync.
    ///
    /// The just-set identifier must reach `IdentityStore` BEFORE `RequestEnqueuer.enqueueProfile`
    /// reads it: the reducer's write-through `defer` fires only at RETURN, which is too late.
    /// So we push identity synchronously here. Crucially we seed the FULL `state.identity` from
    /// `IdentityStore.current` first (minting the anonymousId on first access) so the setter FOLDS
    /// onto the persisted identity — `IdentityStore.update` replaces wholesale, so seeding only the
    /// anonymousId would clobber the other persisted identifiers with `nil` from a fresh pre-init `state`.
    /// Mirrors the pre-init `set(profile:)` path.
    private func setPreInitIdentifier(
        _ state: inout KlaviyoState,
        _ apply: (inout KlaviyoState) -> Void
    ) {
        state.identity = IdentityStore.shared.current
        apply(&state)
        IdentityStore.shared.update(state.identity)
        guard let anonymousId = state.anonymousId else { return }
        let payload = CreateProfilePayload(data: ProfilePayload(
            email: state.email,
            phoneNumber: state.phoneNumber,
            externalId: state.externalId,
            anonymousId: anonymousId
        ))
        RequestEnqueuer.enqueueProfile(payload: payload)
    }
}

extension Store where State == KlaviyoState, Action == KlaviyoAction {
    static let production = Store(
        initialState: KlaviyoState(requestsInFlight: []),
        reducer: KlaviyoReducer()
    )
}
