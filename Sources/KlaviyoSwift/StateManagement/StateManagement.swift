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
                return .task { .flushQueue }
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
                    // Appended so it sends after any queued old-company requests; persisted
                    // synchronously so it survives a crash before the first flush.
                    QueueStore.shared.enqueue(request, persist: .synchronous)
                }
                // NOTE: do NOT clear the push token here — the switch must preserve it so the
                // token can be re-registered under the new company immediately below.
                // Give the new company a clean identity: mint a fresh anon and drop any PII so
                // `.completeInitialization` hydrates it. Unconditional (matches the runtime switch
                // path's `state.reset()`) so an anonymous-only switch does not carry the old
                // company's anon into the new one.
                IdentityStore.shared.update(ProfileData(anonymousId: IdentityStore.shared.mintNewAnonymousId()))
                // Re-register the preserved token under the new company (identity-only, fresh anon).
                if let tokenData = IdentityStore.shared.pushToken,
                   let newAnon = IdentityStore.shared.current.anonymousId {
                    let request = RequestFactory.tokenRequest(
                        apiKey: apiKey,
                        pushToken: tokenData.pushToken,
                        enablement: tokenData.pushEnablement,
                        background: tokenData.pushBackground.rawValue,
                        profile: ProfilePayload(
                            email: nil, phoneNumber: nil, externalId: nil, anonymousId: newAnon
                        )
                    )
                    QueueStore.shared.enqueue(request)
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
            guard email.isNotEmptyOrSame(as: IdentityStore.shared.current.email, identifier: "email") else {
                return .none
            }
            applyIdentifierChange(&state) { $0.email = email.trimWhiteSpaceOrReturnNilIfEmpty() }
            return .none

        case let .setPhoneNumber(phoneNumber):
            guard phoneNumber.isNotEmptyOrSame(
                as: IdentityStore.shared.current.phoneNumber, identifier: "phone number"
            ) else {
                return .none
            }
            applyIdentifierChange(&state) { $0.phoneNumber = phoneNumber.trimWhiteSpaceOrReturnNilIfEmpty() }
            return .none

        case let .setExternalId(externalId):
            guard externalId.isNotEmptyOrSame(
                as: IdentityStore.shared.current.externalId, identifier: "external id"
            ) else {
                return .none
            }
            applyIdentifierChange(&state) { $0.externalId = externalId.trimWhiteSpaceOrReturnNilIfEmpty() }
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
            let newTokenData = PushTokenData(
                pushToken: pushToken, pushEnablement: enablement,
                pushBackground: environment.getBackgroundSetting(),
                deviceData: DeviceMetadata(context: environment.appContextInfo())
            )
            // Dedup against the canonical token: skip when token + enablement + background +
            // device metadata all match.
            guard IdentityStore.shared.pushToken != newTokenData else { return .none }
            // Write-through: assign the projection and let the reducer's `defer` persist it to
            // IdentityStore. Still the load-bearing write method until KlaviyoState and reducer
            // fully go away.
            state.pushTokenData = newTokenData
            guard let anonymousId = IdentityStore.shared.current.anonymousId else {
                environment.emitDeveloperWarning("SDK internal error: missing anonymousId")
                return .none
            }
            // Gate on `state.apiKey` to match `state.enqueueRequest`: `SDKConfigStore` can hold a
            // persisted apiKey before `.initialize` sets `state.apiKey` (warm start), and enqueuing
            // via `enqueueRequest` then would be dropped. The else branch re-gates on
            // `SDKConfigStore`, so a warm-start token still reaches `QueueStore` (not the buffer).
            if let apiKey = state.apiKey {
                // Post-init: fold + consume any pending profile into the registration.
                state.identity = IdentityStore.shared.current
                let request = state.resolvedTokenRequest(
                    apiKey: apiKey, anonymousId: anonymousId, pushToken: pushToken, enablement: enablement
                )
                state.enqueueRequest(request: request)
            } else {
                // Pre-init or warm start: RequestEnqueuer re-gates on SDKConfigStore.
                RequestEnqueuer.enqueuePushToken(pushToken, enablement: enablement)
            }
            return .none

        case let .setPushEnablement(enablement):
            guard let pushToken = IdentityStore.shared.pushToken?.pushToken else {
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
            guard state.apiKey != nil else {
                return .none
            }
            // Lease the durable pending queue into the in-memory in-flight set: `drainAll` atomically
            // snapshots + clears the store (parity with the former `append(contentsOf:)` +
            // `removeAll`). In-flight stays an in-memory reducer field.
            let batch = QueueStore.shared.drainAll()
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
            if state.apiKey != nil, !state.requestsInFlight.isEmpty {
                QueueStore.shared.prepend(state.requestsInFlight, persist: .synchronous)
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
            if state.apiKey != nil, !state.requestsInFlight.isEmpty {
                QueueStore.shared.prepend(state.requestsInFlight, persist: .synchronous)
            }
            state.requestsInFlight = []
            return .none

        case let .enqueueEvent(event):
            RequestEnqueuer.enqueueEvent(event)
            // Post-init only, matching today: publish to the EventBus (drives event-triggered in-app
            // forms via KlaviyoForms' ProfileEventObserver) and prompt-flush high-priority events.
            // Pre-init there is no forms observer and the flush engine no-ops, so gate on init state.
            guard case .initialized = state.initalizationState else { return .none }
            // Stamp identifiers onto the published event so the EventBus/KlaviyoJS path carries the
            // same properties as the outbound request. Read from the canonical stores, matching
            // `RequestEnqueuer.enqueueEvent`.
            let identity = IdentityStore.shared.current
            let publishedEvent = event.updateEventWithIdentifiers(
                email: identity.email,
                phoneNumber: identity.phoneNumber,
                externalId: identity.externalId,
                pushToken: IdentityStore.shared.pushToken?.pushToken
            )
            // `.fireAndForget` keeps publish async and reentrancy-safe, matching the pre-cutover
            // semantics: an EventBus subscriber cannot dispatch back into the store synchronously.
            let publish = EffectTask<KlaviyoAction>.fireAndForget { enrichAndPublishEvent(publishedEvent) }
            return event.priority == .high ? .merge([.task { .flushQueue }, publish]) : publish

        case let .enqueueAggregateEvent(payload):
            RequestEnqueuer.enqueueAggregateEvent(payload)
            return .none

        case let .enqueueProfile(profile):
            state.identity = IdentityStore.shared.current
            let tokenData = IdentityStore.shared.pushToken
            let currentIds = [state.email, state.phoneNumber, state.externalId]
            let incomingIds = [profile.email, profile.phoneNumber, profile.externalId].map {
                // Normalize with the same trimming used by updateStateWithProfile
                // so whitespace-padded inputs match their stored counterparts.
                $0?.trimWhiteSpaceOrReturnNilIfEmpty()
            }
            let identifiersChanged = currentIds != incomingIds
            // Identifier change on an already-identified profile → mint a fresh anonymousId and
            // drop prior PII, so a set(profile:) with different identifiers does not reuse the
            // previous user's anonymousId (which would merge two people onto one profile).
            // resetProfile() remains available for explicitly clobbering all state.
            if state.isIdentified, identifiersChanged {
                state.reset(preserveTokenData: false)
                state.pushTokenData = tokenData
            }
            state.updateStateWithProfile(profile: profile)
            IdentityStore.shared.update(state.identity)
            // Skip the API call entirely when there is nothing new to sync:
            // identifiers are unchanged, the profile carries no extra attributes,
            // and no profile properties are queued up via setProfileProperty.
            if !identifiersChanged, !profile.hasNonIdentifierData, state.pendingProfile == nil {
                return .none
            }
            guard let anonymousId = state.anonymousId else { return .none }
            let profilePayload = state.profilePayload(from: profile, anonymousId: anonymousId)
            RequestEnqueuer.enqueueProfile(payload: CreateProfilePayload(data: profilePayload))
            if let tokenData {
                // Re-register the token as a SEPARATE, identity-only request (built from the current
                // identity, no structured attributes), enqueued after the createProfile above. Because
                // it carries no attributes, it can't overwrite the profile attributes just sent, and
                // FIFO ordering keeps the profile ahead of the registration.
                RequestEnqueuer.enqueuePushToken(tokenData.pushToken, enablement: tokenData.pushEnablement)
            }
            return .none

        case let .enqueueSubscription(subscription):
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

        case .resetProfile:
            // Seed from canonical so `reset` sees the real identity (mint decision + write-back below);
            // the projection can be stale/empty pre-init. Goes away with KlaviyoState eventually.
            state.identity = IdentityStore.shared.current
            let tokenData = IdentityStore.shared.pushToken
            state.reset(preserveTokenData: false)
            state.pushTokenData = tokenData
            IdentityStore.shared.update(state.identity)
            if let tokenData {
                RequestEnqueuer.enqueuePushToken(tokenData.pushToken, enablement: tokenData.pushEnablement)
            }
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
            // Identity is resolved inside `RequestEnqueuer.enqueueTrackingLinkClicked` from the
            // canonical `IdentityStore`. The ungated enqueuer routes to `QueueStore` when an apiKey
            // is present, or buffers durably pre-init. Once the flush engine becomes a Core actor
            // the case will fold into `TrackingLinkManager` entirely.
            RequestEnqueuer.enqueueTrackingLinkClicked(trackingLink: trackingLink, clickTime: clickTime)
            return .none
        }
    }

    /// Applies an identifier change (`setEmail`/`setPhoneNumber`/`setExternalId`) against the
    /// canonical `IdentityStore`, then enqueues the follow-up sync request:
    /// - **Post-init + token present:** enqueues a token re-association request via
    ///   `state.enqueueRequest` (→ `QueueStore.shared`), folding any pending profile.
    /// - **Pre-init or no token:** enqueues a profile via the ungated `RequestEnqueuer`,
    ///   folding any pending profile.
    ///
    /// Seeds the FULL identity from `IdentityStore` first so the setter folds onto the persisted
    /// profile (update replaces wholesale).
    private func applyIdentifierChange(
        _ state: inout KlaviyoState,
        _ apply: (inout KlaviyoState) -> Void
    ) {
        state.identity = IdentityStore.shared.current
        apply(&state)
        IdentityStore.shared.update(state.identity)
        guard let anonymousId = state.anonymousId else { return }

        // The identifier changed, so re-register the profile under the new identity. Two paths,
        // and both fold in + consume any staged `pendingProfile` so those properties ship now
        // instead of waiting for a later flush. (This is the one behavior change from the legacy
        // `setPreInitIdentifier`, which left `pendingProfile` staged.)
        //
        // Gate on `state.apiKey`, not `SDKConfigStore`: on a warm start `initialize` may not have
        // run through the reducer yet, so `state.apiKey` is the source of truth for "post-init".
        if let apiKey = state.apiKey,
           let tokenData = IdentityStore.shared.pushToken {
            // Post-init with a token: re-associate the token to the new identity.
            let request = state.resolvedTokenRequest(
                apiKey: apiKey,
                anonymousId: anonymousId,
                pushToken: tokenData.pushToken,
                enablement: tokenData.pushEnablement
            )
            state.enqueueRequest(request: request) // already targets QueueStore.shared
        } else {
            // Pre-init or post-init with no token: send a profile via the ungated RequestEnqueuer
            // (pre-init, this lands in the durable buffer). Empty `Profile()` is intentional —
            // `profilePayload(from:anonymousId:)` reads every identifier straight from `state`,
            // at this point, so the argument would only carry redundant values.
            let payload = CreateProfilePayload(data: state.profilePayload(
                from: Profile(),
                anonymousId: anonymousId
            ))
            RequestEnqueuer.enqueueProfile(
                payload: state.updateRequestAndStateWithPendingProfile(profile: payload)
            )
        }
    }
}

extension Store where State == KlaviyoState, Action == KlaviyoAction {
    static let production = Store(
        initialState: KlaviyoState(requestsInFlight: []),
        reducer: KlaviyoReducer()
    )
}
