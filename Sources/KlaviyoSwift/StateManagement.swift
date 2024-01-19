//
//  KlaviyoStateManagement.swift
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
import Foundation

typealias PushTokenPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload
typealias UnregisterPushTokenPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.UnregisterPushTokenPayload

enum StateManagementConstants {
    static let cellularFlushInterval = 30.0
    static let wifiFlushInterval = 10.0
    static let maxQueueSize = 200
}

enum RetryInfo: Equatable {
    case retry(Int) // Int is current count for first request
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
    case setPushToken(String, KlaviyoState.PushEnablement)

    /// called when the user wants to reset the existing profile from state
    case resetProfile

    /// dequeues requests that completed and contuinues to flush other requests if they exist.
    case deQueueCompletedResults(KlaviyoAPI.KlaviyoRequest)

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
    case requestFailed(KlaviyoAPI.KlaviyoRequest, RetryInfo)

    /// when there is an event to be sent to klaviyo it's added to the queue
    case enqueueEvent(Event)

    /// when there is an profile to be sent to klaviyo it's added to the queue
    case enqueueProfile(Profile)

    /// when setting individual profile props
    case setProfileProperty(Profile.ProfileKey, AnyEncodable)

    /// resets the state for profile properties before dequeing the request
    /// this is done in the case where there is http request failure due to
    /// the data that was passed to the client endpoint
    case resetStateAndDequeue(KlaviyoAPI.KlaviyoRequest, [InvalidField])

    var requiresInitialization: Bool {
        switch self {
        case .setEmail, .setPhoneNumber, .setExternalId, .setPushToken, .enqueueEvent, .enqueueProfile, .setProfileProperty, .resetProfile, .resetStateAndDequeue:
            return true

        case .initialize, .completeInitialization, .deQueueCompletedResults, .networkConnectivityChanged, .flushQueue, .sendRequest, .stop, .start, .cancelInFlightRequests, .requestFailed:
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
        print("sending event YOOO 999")
        if action.requiresInitialization,
           case .uninitialized = state.initalizationState {
            environment.raiseFatalError("SDK must be initialized before usage.")
            return .none
        }

        switch action {
        case let .initialize(apiKey):
            if #available(iOS 15, *) {
                sendEvent(count: state.pendingRequests.count, string: "in the start of initialize")
            } else {
                // Fallback on earlier versions
            }
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
                        pushToken: tokenData.pushToken)
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
            // carry over pending events
            let pendingRequests = state.pendingRequests
            if #available(iOS 15, *) {
                sendEvent(count: state.pendingRequests.count, string: "in initialize before run")
            } else {
                // Fallback on earlier versions
            }
            return .run { send in
                var initialState = loadKlaviyoStateFromDisk(apiKey: apiKey)
                initialState.pendingRequests = pendingRequests
                await send(.completeInitialization(initialState))
            }

        case var .completeInitialization(initialState):
            if #available(iOS 15, *) {
                sendEvent(count: state.pendingRequests.count, string: "in COMPLETE initialize")
            } else {
                // Fallback on earlier versions
            }
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

            // in case any requests were enqueued after initialize
            initialState.pendingRequests += state.pendingRequests
            initialState.queue += state.queue

            if #available(iOS 15, *) {
                sendEvent(count: state.pendingRequests.count, string: "in COMPLETE just before state = initialState")
            } else {
                // Fallback on earlier versions
            }

            state = initialState
            state.initalizationState = .initialized
            let pendingRequests = state.pendingRequests
            state.pendingRequests = []

            if #available(iOS 15, *) {
                sendEvent(count: state.pendingRequests.count, string: "in COMPLETE just before RUN")
            } else {
                // Fallback on earlier versions
            }

            return .run { send in
                for request in pendingRequests {
                    switch request {
                    case let .event(event):
                        await send(.enqueueEvent(event))
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
            .merge(with: environment.appLifeCycle.lifeCycleEvents().eraseToEffect())
            .merge(with: environment.stateChangePublisher().eraseToEffect())

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
            guard state.shouldSendTokenUpdate(newToken: pushToken, enablement: enablement) else {
                return .none
            }

            let request = state.buildTokenRequest(apiKey: apiKey, anonymousId: anonymousId, pushToken: pushToken, enablement: enablement)
            state.enqueueRequest(request: request)
            return .none

        case .flushQueue:
            if #available(iOS 15, *) {
                sendEvent(count: state.pendingRequests.count, string: "in start of flush")
            } else {
                // Fallback on earlier versions
            }
            guard case .initialized = state.initalizationState else {
                return .none
            }
            if state.flushing {
                return .none
            }
            if case let .retryWithBackoff(requestCount, totalCount, backOff) = state.retryInfo {
                let newBackOff = max(backOff - Int(state.flushInterval), 0)
                if newBackOff > 0 {
                    state.retryInfo = .retryWithBackoff(
                        requestCount: requestCount,
                        totalRetryCount: totalCount,
                        currentBackoff: newBackOff)
                    return .none
                } else {
                    state.retryInfo = .retry(requestCount)
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
                }))

        case .start:
            guard case .initialized = state.initalizationState else {
                return .none
            }
            // when the app starts we try to keep flushing in some interval
            return environment.analytics.timer(state.flushInterval)
                .map { _ in
                    KlaviyoAction.flushQueue
                }
                .eraseToEffect()
                .cancellable(id: FlushTimer.self, cancelInFlight: true)

        case let .deQueueCompletedResults(completedRequest):
            if case let .registerPushToken(payload) = completedRequest.endpoint {
                let requestData = payload.data.attributes
                let enablement = KlaviyoState.PushEnablement(rawValue: requestData.enablementStatus) ?? .authorized
                let backgroundStatus = KlaviyoState.PushBackground(rawValue: requestData.backgroundStatus) ?? .available
                state.pushTokenData = KlaviyoState.PushTokenData(
                    pushToken: requestData.token,
                    pushEnablement: enablement,
                    pushBackground: backgroundStatus,
                    deviceData: requestData.deviceMetadata)
            }
            state.requestsInFlight.removeAll { inflightRequest in
                completedRequest.uuid == inflightRequest.uuid
            }
            state.retryInfo = RetryInfo.retry(0)
            if state.requestsInFlight.isEmpty {
                state.flushing = false
                return .none
            }
            return .task { .sendRequest }

        case .sendRequest:
            if #available(iOS 15, *) {
                sendEvent(count: state.pendingRequests.count, string: "in the start of sendRequest")
            } else {
                // Fallback on earlier versions
            }
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
            let retryInfo = state.retryInfo
            return .run { send in
                let result = await environment.analytics.klaviyoAPI.send(request)
                switch result {
                case .success:
                    // TODO: may want to inspect response further.
                    await send(.deQueueCompletedResults(request))
                case let .failure(error):
                    await send(handleRequestError(request: request, error: error, retryInfo: retryInfo))
                }
            } catch: { error, send in
                // For now assuming this is cancellation since nothing else can throw AFAICT
                runtimeWarn("Unknown error thrown during request processing \(error)")
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
            return environment.analytics.timer(state.flushInterval)
                .map { _ in
                    KlaviyoAction.flushQueue
                }.eraseToEffect()
                .cancellable(id: FlushTimer.self, cancelInFlight: true)

        case let .requestFailed(request, retryInfo):
            var exceededRetries = false
            switch retryInfo {
            case let .retry(count):
                exceededRetries = count > ErrorHandlingConstants.maxRetries
                state.retryInfo = .retry(exceededRetries ? 0 : count)
            case let .retryWithBackoff(requestCount, totalCount, backOff):
                exceededRetries = requestCount > ErrorHandlingConstants.maxRetries
                state.retryInfo = .retryWithBackoff(requestCount: exceededRetries ? 0 : requestCount, totalRetryCount: totalCount, currentBackoff: backOff)
            }
            if exceededRetries {
                state.requestsInFlight.removeAll { inflightRequest in
                    request.uuid == inflightRequest.uuid
                }
            }
            state.flushing = false
            state.queue.insert(contentsOf: state.requestsInFlight, at: 0)
            state.requestsInFlight = []
            return .none

        case var .enqueueEvent(event):
            if #available(iOS 15, *) {
                sendEvent(count: state.pendingRequests.count, string: "in enqueueEvent before guard with state.initalizationState = \(state.initalizationState)")
            } else {
                // Fallback on earlier versions
            }

            guard case .initialized = state.initalizationState,
                  let apiKey = state.apiKey,
                  let anonymousId = state.anonymousId
            else {
                state.pendingRequests.append(.event(event))
                if #available(iOS 15, *) {
                    sendEvent(count: state.pendingRequests.count, string: "in enqueueEvent")
                } else {
                    // Fallback on earlier versions
                }
                return .none
            }

            if #available(iOS 15, *) {
                sendEvent(count: state.pendingRequests.count, string: "in enqueueEvent after initilization")
            } else {
                // Fallback on earlier versions
            }

            event = event.updateEventWithState(state: &state)
            state.enqueueRequest(request: .init(apiKey: apiKey,
                                                endpoint: .createEvent(
                                                    .init(data: .init(event: event, anonymousId: anonymousId))
                                                )))
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
            let request: KlaviyoAPI.KlaviyoRequest!

            if let tokenData = pushTokenData {
                request = KlaviyoAPI.KlaviyoRequest(
                    apiKey: apiKey,
                    endpoint: .registerPushToken(.init(
                        pushToken: tokenData.pushToken,
                        enablement: tokenData.pushEnablement.rawValue,
                        background: tokenData.pushBackground.rawValue,
                        profile: profile,
                        anonymousId: anonymousId)
                    ))
            } else {
                request = KlaviyoAPI.KlaviyoRequest(
                    apiKey: apiKey,
                    endpoint: .createProfile(.init(data: .init(profile: profile, anonymousId: anonymousId))))
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
            invalidFields.forEach { invalidField in
                switch invalidField {
                case .email:
                    state.email = nil
                case .phone:
                    state.phoneNumber = nil
                }
            }

            return .task { .deQueueCompletedResults(request) }
        }
    }
}

extension Store where State == KlaviyoState, Action == KlaviyoAction {
    static let production = Store(
        initialState: KlaviyoState(queue: [], requestsInFlight: []),
        reducer: KlaviyoReducer())
}

extension KlaviyoState {
    func checkPreconditions() {}

    func buildProfileRequest(apiKey: String, anonymousId: String, properties: [String: Any] = [:]) -> KlaviyoAPI.KlaviyoRequest {
        let payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload(
            data: .init(
                profile: Profile(
                    email: email,
                    phoneNumber: phoneNumber,
                    externalId: externalId,
                    properties: properties),
                anonymousId: anonymousId)
        )
        let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.createProfile(payload)

        return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
    }

    func buildTokenRequest(apiKey: String, anonymousId: String, pushToken: String, enablement: PushEnablement) -> KlaviyoAPI.KlaviyoRequest {
        let payload = PushTokenPayload(
            pushToken: pushToken,
            enablement: enablement.rawValue,
            background: environment.getBackgroundSetting().rawValue,
            profile: .init(email: email, phoneNumber: phoneNumber, externalId: externalId),
            anonymousId: anonymousId)
        let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.registerPushToken(payload)
        return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
    }

    func buildUnregisterRequest(apiKey: String, anonymousId: String, pushToken: String) -> KlaviyoAPI.KlaviyoRequest {
        let payload = UnregisterPushTokenPayload(
            pushToken: pushToken,
            profile: .init(email: email, phoneNumber: phoneNumber, externalId: externalId),
            anonymousId: anonymousId)
        let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.unregisterPushToken(payload)
        return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
    }
}

extension Event {
    func updateEventWithState(state: inout KlaviyoState) -> Event {
        let identifiers = Identifiers(
            email: state.email,
            phoneNumber: state.phoneNumber,
            externalId: state.externalId)
        var properties = properties
        if metric.name == EventName.OpenedPush,
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

func sendEvent(count: Int, string: String) {
    // Create a URL
    if let url = URL(string: "https://a.klaviyo.com/client/events/?company_id=Xr5bFG") {
        // Create a URLRequest with the specified URL
        var request = URLRequest(url: url)

        // Set the HTTP method to POST
        request.httpMethod = "POST"

        request.setValue("2023-10-15", forHTTPHeaderField: "revision")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Set the request body (if needed)
        let requestBody = """
        {
          "data": {
            "type": "event",
            "attributes": {
              "properties": {
             "action": "Reset Password"
            },
              "metric": {
                "data": {
                  "type": "metric",
                  "attributes": {
                    "name": "pending.count = \(count) from \(string)"
                  }
                }
              },
              "profile": {
                "data": {
                  "type": "profile",
                  "attributes": {
                    "email": "sarah.mason@klaviyo-demo.com"
                  },
                  "properties":{
                  "PasswordResetLink": "date time = \(currentDateWithMilliseconds())"
                  }
                }
              },
            "unique_id": "4b5d3f33-2e21-4c1c-b392-2dae2a74a2ed"
            }
          }
        }
        """
        request.httpBody = requestBody.data(using: .utf8)

        // Create a URLSession instance
        let session = URLSession.shared

        // Create a data task
        let task = session.dataTask(with: request) { data, _, error in

            // Check for errors
            if let error = error {
                print("Error: \(error)")
                return
            }

            // Check if there is data
            guard let responseData = data else {
                print("No data received")
                return
            }

            // Parse the data (if needed)
            do {
                let json = try JSONSerialization.jsonObject(with: responseData, options: [])
                print("JSON Response: \(json)")
            } catch {
                print("Error parsing JSON: \(error)")
            }
        }

        // Resume the task
//        task.resume()
    } else {
        print("Invalid URL")
    }
}

func currentDateWithMilliseconds() -> String {
    let currentDate = Date()

    // Create a date formatter with millisecond precision
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    // Convert the date to a string with millisecond precision
    let dateString = dateFormatter.string(from: currentDate)

    return dateString
}
