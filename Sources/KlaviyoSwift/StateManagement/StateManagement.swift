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
import UIKit
import UserNotifications

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
    /// Sets the API key to state. If the state is already initialized then the push token is moved over to the company with the API key provided in this action.
    /// Loads the state from disk and carries over existing items from the queue. This emits `completeInitialization` at the end with the state loaded from disk.
    case initialize(String)

    /// after the SDK is initialized, creates an initial state from existing state from disk (if it exists) and queues up any tasks that are pending
    case completeInitialization(KlaviyoState)

    /// if initialized, set the email else queue it up
    case setEmail(String)

    /// if initialized set the phone number else queue it up
    case setPhoneNumber(String)

    /// if initialized set the external id else queue it up
    case setExternalId(String)

    /// call when a new push token needs to be set. If this token is the same we don't perform a network request to register the token
    case setPushToken(String, PushEnablement)

    /// call this to sync the user's local push notification authorization setting with the user's profile on the Klaviyo back-end.
    case setPushEnablement(PushEnablement)

    /// call to set the app badge count as well as update the stored value in the User Defaults suite
    case setBadgeCount(Int)

    /// call to sync the stored value in the User Defaults suite with the currently displayed badge count provided by `UIApplication.shared.applicationIconBadgeNumber`
    case syncBadgeCount

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

    /// when setting individual profile props
    case setProfileProperty(Profile.ProfileKey, AnyEncodable)

    /// resets the state for profile properties before dequeing the request
    /// this is done in the case where there is http request failure due to
    /// the data that was passed to the client endpoint
    case resetStateAndDequeue(KlaviyoRequest, [InvalidField])

    case trackingLinkReceived(URL)

    case trackingLinkDestinationResolved(URL)

    /// open a deep link URL originating from a Klaviyo notification
    case openDeepLink(URL)

    var requiresInitialization: Bool {
        switch self {
        // if event metric is opened push we DON'T require initilization in all other event metric cases we DO.
        case let .enqueueEvent(event) where event.metric.name == ._openedPush:
            return false
        case .enqueueAggregateEvent, .enqueueEvent, .enqueueProfile, .resetProfile, .resetStateAndDequeue, .setBadgeCount, .setEmail, .setExternalId, .setPhoneNumber, .setProfileProperty, .setPushEnablement, .setPushToken:
            return true

        case .cancelInFlightRequests, .completeInitialization, .deQueueCompletedResults, .flushQueue, .initialize, .networkConnectivityChanged, .requestFailed, .sendRequest, .start, .stop, .syncBadgeCount, .trackingLinkReceived, .trackingLinkDestinationResolved, .openDeepLink:
            return false
        }
    }
}

struct RequestId {}
struct FlushTimer {}

struct KlaviyoReducer: ReducerProtocol {
    typealias State = KlaviyoState
    typealias Action = KlaviyoAction

    func reduce(into state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> {
        if action.requiresInitialization,
           case .uninitialized = state.initalizationState {
            environment.emitDeveloperWarning("SDK must be initialized before usage.")
            return .none
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
                    let request = state.buildUnregisterRequest(
                        apiKey: apiKey,
                        anonymousId: anonymousId,
                        pushToken: tokenData.pushToken
                    )
                    state.enqueueRequest(request: request)
                }
                state.apiKey = apiKey
                state.reset()
            }
            guard case .uninitialized = state.initalizationState else {
                return .none
            }
            state.initalizationState = .initializing
            state.apiKey = apiKey
            return .run { send in
                let initialState = loadKlaviyoStateFromDisk(apiKey: apiKey)
                await send(.completeInitialization(initialState))
            }

        case var .completeInitialization(initialState):
            guard case .initializing = state.initalizationState else {
                return .none
            }
            if let email = state.email {
                initialState.email = email
            }
            if let phoneNumber = state.phoneNumber {
                initialState.phoneNumber = phoneNumber
            }
            if let externalId = state.externalId {
                initialState.externalId = externalId
            }
            // For any requests that get added between initilizing and initilized.
            // Ex: when the app is invoked from a push notification after being killed from the app switcher.
            let pendingRequests = state.pendingRequests
            initialState.queue += state.queue

            state = initialState
            state.initalizationState = .initialized

            state.pendingRequests = []

            return .run { send in
                for request in pendingRequests {
                    switch request {
                    case let .event(event):
                        await send(.enqueueEvent(event))
                    case let .aggregateEvent(payload):
                        await send(.enqueueAggregateEvent(payload))
                    case let .profile(profile):
                        await send(.enqueueProfile(profile))
                    case let .pushToken(token, enablement):
                        await send(.setPushToken(token, enablement))
                    case let .setEmail(email):
                        await send(.setEmail(email))
                    case let .setExternalId(externalId):
                        await send(.setExternalId(externalId))
                    case let .setPhoneNumber(phoneNumber):
                        await send(.setPhoneNumber(phoneNumber))
                    }
                }
                await send(.start)
            }
            .merge(with: environment.lifecycleEventsWithReachability().map(\.transformToKlaviyoAction).eraseToEffect())
            .merge(with: klaviyoSwiftEnvironment.stateChangePublisher().eraseToEffect())

        case let .setEmail(email):
            guard case .initialized = state.initalizationState else {
                state.pendingRequests.append(.setEmail(email))
                return .none
            }
            state.updateEmail(email: email)
            return .none

        case let .setPhoneNumber(phoneNumber):
            guard case .initialized = state.initalizationState else {
                state.pendingRequests.append(.setPhoneNumber(phoneNumber))
                return .none
            }
            state.updatePhoneNumber(phoneNumber: phoneNumber)
            return .none

        case let .setExternalId(externalId):
            guard case .initialized = state.initalizationState else {
                state.pendingRequests.append(.setExternalId(externalId))
                return .none
            }
            state.updateExternalId(externalId: externalId)
            return .none

        case let .setPushToken(pushToken, enablement):
            guard case .initialized = state.initalizationState, let apiKey = state.apiKey, let anonymousId = state.anonymousId else {
                state.pendingRequests.append(.pushToken(pushToken, enablement))
                return .none
            }
            if !state.shouldSendTokenUpdate(newToken: pushToken, enablement: enablement) {
                return .none
            }

            let request = state.buildTokenRequest(apiKey: apiKey, anonymousId: anonymousId, pushToken: pushToken, enablement: enablement)
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

            if state.queue.isEmpty {
                return .none
            }

            state.requestsInFlight.append(contentsOf: state.queue)
            state.queue.removeAll()
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
                    await send(KlaviyoAction.syncBadgeCount)
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
                        await send(KlaviyoAction.setBadgeCount(0))
                    } else {
                        await send(KlaviyoAction.syncBadgeCount)
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
                state.pushTokenData = KlaviyoState.PushTokenData(
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
            state.queue.insert(contentsOf: state.requestsInFlight, at: 0)
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
            state.queue.insert(contentsOf: state.requestsInFlight, at: 0)
            state.requestsInFlight = []
            return .none

        case var .enqueueEvent(event):
            guard case .initialized = state.initalizationState,
                  let apiKey = state.apiKey,
                  let anonymousId = state.anonymousId
            else {
                state.pendingRequests.append(.event(event))
                return .none
            }

            event = event.updateEventWithState(state: &state)

            let payload = CreateEventPayload(
                data: CreateEventPayload.Event(
                    name: event.metric.name.value,
                    properties: event.properties,
                    email: event.identifiers?.email,
                    phoneNumber: event.identifiers?.phoneNumber,
                    externalId: event.identifiers?.externalId,
                    anonymousId: anonymousId,
                    value: event.value,
                    time: event.time,
                    uniqueId: event.uniqueId,
                    pushToken: state.pushTokenData?.pushToken
                ))

            let endpoint = KlaviyoEndpoint.createEvent(apiKey, payload)
            let request = KlaviyoRequest(endpoint: endpoint)

            state.enqueueRequest(request: request)

            /*
             if we receive an opened push event we want to flush the queue right away so that
             we don't miss any user engagement events. In all other cases we will flush the queue
             using the flush intervals defined above in `StateManagementConstants`
             */
            return event.metric.name == ._openedPush ? .task { .flushQueue } : .none

        case let .enqueueAggregateEvent(payload):
            guard case .initialized = state.initalizationState,
                  let apiKey = state.apiKey
            else {
                state.pendingRequests.append(.aggregateEvent(payload))
                return .none
            }

            let endpoint = KlaviyoEndpoint.aggregateEvent(apiKey, payload)
            let request = KlaviyoRequest(endpoint: endpoint)

            state.enqueueRequest(request: request)

            return .none

        case let .enqueueProfile(profile):
            guard case .initialized = state.initalizationState
            else {
                state.pendingRequests.append(.profile(profile))
                return .none
            }

            let pushTokenData = state.pushTokenData
            state.reset(preserveTokenData: false)
            state.updateStateWithProfile(profile: profile)
            guard let anonymousId = state.anonymousId,
                  let apiKey = state.apiKey
            else {
                return .none
            }
            let request: KlaviyoRequest!

            let profilePayload = profile.toAPIModel(
                email: state.email,
                phoneNumber: state.phoneNumber,
                externalId: state.externalId,
                anonymousId: anonymousId
            )

            if let tokenData = pushTokenData {
                let payload = PushTokenPayload(
                    pushToken: tokenData.pushToken,
                    enablement: tokenData.pushEnablement.rawValue,
                    background: tokenData.pushBackground.rawValue,
                    profile: profilePayload
                )
                request = KlaviyoRequest(
                    endpoint: KlaviyoEndpoint.registerPushToken(apiKey, payload)
                )
            } else {
                request = KlaviyoRequest(
                    endpoint: KlaviyoEndpoint.createProfile(apiKey, CreateProfilePayload(data: profilePayload))
                )
            }
            state.enqueueRequest(request: request)

            return .none

        case let .setBadgeCount(count):
            return .run { _ in
                _ = klaviyoSwiftEnvironment.setBadgeCount(count)
            }

        case .syncBadgeCount:
            Task {
                await MainActor.run {
                    if let userDefaults = UserDefaults(suiteName: Bundle.main.object(forInfoDictionaryKey: "klaviyo_app_group") as? String) {
                        userDefaults.set(UIApplication.shared.applicationIconBadgeNumber, forKey: "badgeCount")
                    }
                }
            }
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

        case let .trackingLinkReceived(from: trackingLinkURL):
            if #available(iOS 14.0, *) {
                Logger.stateLogger.info("Attempting to resolve tracking link destination from tracking URL '\(trackingLinkURL.absoluteString)'")
            }

            let profileInfo = ProfilePayload(
                email: state.email,
                phoneNumber: state.phoneNumber,
                externalId: state.externalId,
                anonymousId: state.anonymousId ?? ""
            )

            return .run { _ in
                do {
                    let endpoint = KlaviyoEndpoint.resolveDestinationURL(
                        trackingLink: trackingLinkURL,
                        profileInfo: profileInfo
                    )
                    let klaviyoRequest = KlaviyoRequest(endpoint: endpoint)
                    let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: endpoint.maxRetries)
                    let result = await environment.klaviyoAPI.send(klaviyoRequest, attemptInfo)

                    switch result {
                    case let .success(data):
                        let response: TrackingLinkDestinationResponse = try environment.decoder.decode(data)
                        let destinationURL = response.destinationLink

                        if #available(iOS 14.0, *) {
                            Logger.stateLogger.info("Successfully resolved tracking link destination. Destination URL: '\(destinationURL.absoluteString)'")
                        }

                    // TODO: [CHNL-23276] handle destination URL
                    // example:
                    // await send(.navigateToDestinationURL(destinationURL))
                    case let .failure(error):
                        if #available(iOS 14.0, *) {
                            Logger.stateLogger.warning("Unable to resolve tracking link destination; error: '\(error)'")
                        }
                        // TODO: [CHNL-22886] handle error
                    }
                } catch {
                    if #available(iOS 14.0, *) {
                        Logger.stateLogger.warning("Unable to resolve tracking link destination; error: '\(error)'")
                    }
                    // TODO: [CHNL-22886] handle error
                }
            }

        case let .trackingLinkDestinationResolved(url):
            return .run { send in
                await send(.openDeepLink(url))
            }

        case let .openDeepLink(url):
            return .run { _ in
                await environment.openURL(url)
            }
        }
    }
}

extension Store where State == KlaviyoState, Action == KlaviyoAction {
    static let production = Store(
        initialState: KlaviyoState(queue: [], requestsInFlight: []),
        reducer: KlaviyoReducer()
    )
}

extension Event {
    func updateEventWithState(state: inout KlaviyoState) -> Event {
        let identifiers = Identifiers(
            email: state.email,
            phoneNumber: state.phoneNumber,
            externalId: state.externalId
        )
        var properties = properties
        if metric.name == EventName._openedPush,
           let pushToken = state.pushTokenData?.pushToken {
            properties["push_token"] = pushToken
        }
        return Event(name: metric.name,
                     properties: properties,
                     identifiers: identifiers,
                     value: value,
                     time: time,
                     uniqueId: uniqueId)
    }
}
