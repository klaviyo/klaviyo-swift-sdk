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

import Foundation
import KlaviyoCore
import KlaviyoSDKDependencies
import UIKit
import UserNotifications

enum StateManagementConstants {
    static let cellularFlushInterval = 30.0
    static let wifiFlushInterval = 10.0
    static let maxQueueSize = 200
    static let initialAttempt = 1
}

enum RetryInfo: Equatable {
    case retry(Int) // Int is current count for first request
    case retryWithBackoff(requestCount: Int, totalRetryCount: Int, currentBackoff: Int)
}

enum KlaviyoAction: Equatable, Sendable {
    /// Sets the API key to state. If the state is already initialized then the push token is moved over to the company with the API key provided in this action.
    /// Loads the state from disk and carries over existing items from the queue. This emits `completeInitialization` at the end with the state loaded from disk.
    case initialize(String, AppContextInfo)

    /// after the SDK is initialized, creates an initial state from existing state from disk (if it exists) and queues up any tasks that are pending
    case completeInitialization(KlaviyoState)

    /// if initialized, set the email else queue it up
    case setEmail(String, AppContextInfo)

    /// if initialized set the phone number else queue it up
    case setPhoneNumber(String, AppContextInfo)

    /// if initialized set the external id else queue it up
    case setExternalId(String, AppContextInfo)

    /// call when a new push token needs to be set. If this token is the same we don't perform a network request to register the token
    case setPushToken(String, PushEnablement, PushBackground, AppContextInfo)

    /// call this to sync the user's local push notification authorization setting with the user's profile on the Klaviyo back-end.
    case setPushEnablement(PushEnablement, PushBackground, AppContextInfo)

    /// call to set the app badge count as well as update the stored value in the User Defaults suite
    case setBadgeCount(Int)

    /// called when the user wants to reset the existing profile from state
    case resetProfile(AppContextInfo)

    /// dequeues requests that completed and contuinues to flush other requests if they exist.
    case deQueueCompletedResults(KlaviyoRequest)

    /// when the network connectivity change we want to use a different flush interval to flush out the pending requests
    case networkConnectivityChanged(Reachability.NetworkStatus)

    /// flushes the queue say when the app is foregrounded or we come back to having network from not having
    case flushQueue(AppContextInfo)

    /// picks up in flight requests and sends them out. handles errors and if no errors emits a `dequeCompletedResults`
    case sendRequest

    /// call when the app is backgrounded or terminated
    case stop

    /// call after initialization or when the app is foregrounded. This action will  flush the queue at some predefined intervals
    case start

    /// cancels any in flight requests. this can be called when there is no network or from `stop` when app is going to be backgrounded
    case cancelInFlightRequests

    /// called when there is a network or rate limit error
    case requestFailed(KlaviyoRequest, RetryInfo)

    /// when there is an event to be sent to klaviyo it's added to the queue
    case enqueueEvent(Event, AppContextInfo)

    /// when there is an profile to be sent to klaviyo it's added to the queue
    case enqueueProfile(Profile, AppContextInfo)

    /// when setting individual profile props
    case setProfileProperty(Profile.ProfileKey, AnyEncodable)

    // fetches any active in-app forms that should be shown to the user
    case fetchForms

    // handles the full forms response from the server
    case handleFormsResponse(FullFormsResponse)

    /// resets the state for profile properties before dequeing the request
    /// this is done in the case where there is http request failure due to
    /// the data that was passed to the client endpoint
    case resetStateAndDequeue(KlaviyoRequest, [InvalidField])

    var requiresInitialization: Bool {
        switch self {
        // if event metric is opened push we DON'T require initilization in all other event metric cases we DO.
        case let .enqueueEvent(event, _) where event.metric.name == ._openedPush:
            return false

        case .setEmail, .setPhoneNumber, .setExternalId, .setPushToken, .setPushEnablement, .enqueueProfile, .setProfileProperty, .setBadgeCount, .resetProfile, .resetStateAndDequeue, .enqueueEvent, .fetchForms, .handleFormsResponse:
            return true

        case .initialize, .completeInitialization, .deQueueCompletedResults, .networkConnectivityChanged, .flushQueue, .sendRequest, .stop, .start, .cancelInFlightRequests, .requestFailed:
            return false
        }
    }
}

enum CancelIds {
    case request
    case timer
}

struct KlaviyoReducer: Reducer {
    typealias State = KlaviyoState
    typealias Action = KlaviyoAction

    var body: any Reducer {
        Reduce { state, action in
            reduce(into: &state, action: action)
        }
    }

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        if action.requiresInitialization,
           case .uninitialized = state.initalizationState {
            environment.logger.error("SDK must be initialized before usage.")
            return .none
        }

        switch action {
        case let .initialize(apiKey, appContextInfo):
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
                state.reset(preserveTokenData: true, appContextInfo: appContextInfo)
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
                    case let .event(event, appContextInfo):
                        await send(.enqueueEvent(event, appContextInfo))
                    case let .profile(profile, appContextInfo):
                        await send(.enqueueProfile(profile, appContextInfo))
                    case let .pushToken(token, enablement, background, appContextInfo):
                        await send(.setPushToken(token, enablement, background, appContextInfo))
                    case let .setEmail(email, appContextInfo):
                        await send(.setEmail(email, appContextInfo))
                    case let .setExternalId(externalId, appContextInfo):
                        await send(.setExternalId(externalId, appContextInfo))
                    case let .setPhoneNumber(phoneNumber, appContextInfo):
                        await send(.setPhoneNumber(phoneNumber, appContextInfo))
                    }
                }
                await send(.start)
            }
            .merge(with: .run { send in
                let lifeCyclePublisher = await MainActor.run { klaviyoSwiftEnvironment.lifeCyclePublisher()
                }
                for await action in lifeCyclePublisher {
                    await send(action)
                }
            })
            .merge(with: .run { _ in
                let publisher = await MainActor.run { klaviyoSwiftEnvironment.stateChangePublisher()
                }
                for await state in publisher {
                    saveKlaviyoState(state: state)
                }
            })

        case let .setEmail(email, appContextInfo):
            guard case .initialized = state.initalizationState else {
                state.pendingRequests.append(.setEmail(email, appContextInfo))
                return .none
            }
            state.updateEmail(email: email, appContextInfo: appContextInfo)
            return .none

        case let .setPhoneNumber(phoneNumber, appContextInfo):
            guard case .initialized = state.initalizationState else {
                state.pendingRequests.append(.setPhoneNumber(phoneNumber, appContextInfo))
                return .none
            }
            state.updatePhoneNumber(phoneNumber: phoneNumber, appContextInfo: appContextInfo)
            return .none

        case let .setExternalId(externalId, appContextInfo):
            guard case .initialized = state.initalizationState else {
                state.pendingRequests.append(.setExternalId(externalId, appContextInfo))
                return .none
            }
            state.updateExternalId(externalId: externalId, appContextInfo: appContextInfo)
            return .none

        case let .setPushToken(pushToken, enablement, background, appContextInfo):
            guard case .initialized = state.initalizationState, let apiKey = state.apiKey, let anonymousId = state.anonymousId else {
                state.pendingRequests.append(.pushToken(pushToken, enablement, background, appContextInfo))
                return .none
            }
            if !state.shouldSendTokenUpdate(newToken: pushToken, enablement: enablement, appContextInfo: appContextInfo, pushBackground: background) {
                return .none
            }
            let request = state.buildTokenRequest(apiKey: apiKey, anonymousId: anonymousId, pushToken: pushToken, enablement: enablement, background: background, appContextInfo: appContextInfo)
            state.enqueueRequest(request: request)
            return .none

        case let .setPushEnablement(enablement, background, appContextInfo):
            guard let pushToken = state.pushTokenData?.pushToken else {
                return .none
            }

            return .send(KlaviyoAction.setPushToken(pushToken, enablement, background, appContextInfo))

        case let .flushQueue(appContextInfo):
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
                state.enqueueProfileOrTokenRequest(appConextInfo: appContextInfo)
            }

            if state.queue.isEmpty {
                return .none
            }

            state.requestsInFlight.append(contentsOf: state.queue)
            state.queue.removeAll()
            state.flushing = true
            return .send(.sendRequest)

        case .stop:
            guard case .initialized = state.initalizationState else {
                return .none
            }
            return Effect.cancel(id: CancelIds.request)
                .concatenate(with: Effect.cancel(id: CancelIds.timer))
                .concatenate(with: .send(.cancelInFlightRequests))
        case .start:
            guard case .initialized = state.initalizationState else {
                return .none
            }

            let flushInterval = state.flushInterval
            return .merge([
                .run { send in
                    let settings = await environment.getNotificationSettings()
                    let background = await klaviyoSwiftEnvironment.getBackgroundSetting()
                    let appContextInfo = await environment.appContextInfo()
                    await send(KlaviyoAction.setPushEnablement(settings, background, appContextInfo))
                    let autoclearing = await environment.getBadgeAutoClearingSetting()
                    if autoclearing {
                        await send(KlaviyoAction.setBadgeCount(0))
                    }
                },
                .run { send in
                    for await _ in environment.timer(flushInterval) {
                        await send(KlaviyoAction.flushQueue(environment.appContextInfo()))
                    }
                }
                .cancellable(id: CancelIds.timer, cancelInFlight: true)
            ])

        case let .deQueueCompletedResults(completedRequest):
            if case let .registerPushToken(payload) = completedRequest.endpoint {
                let requestData = payload.data.attributes
                let enablement = PushEnablement(rawValue: requestData.enablementStatus) ?? .authorized
                let backgroundStatus = PushBackground(rawValue: requestData.backgroundStatus) ?? .available
                state.pushTokenData = KlaviyoState.PushTokenData(
                    pushToken: requestData.token,
                    pushEnablement: enablement,
                    pushBackground: backgroundStatus,
                    deviceData: requestData.deviceMetadata)
            }
            state.requestsInFlight.removeAll { inflightRequest in
                completedRequest.uuid == inflightRequest.uuid
            }
            state.retryInfo = RetryInfo.retry(StateManagementConstants.initialAttempt)
            if state.requestsInFlight.isEmpty {
                state.flushing = false
                return .none
            }
            return .send(.sendRequest).cancellable(id: CancelIds.request)

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
            let retryInfo = state.retryInfo
            var numAttempts = 1
            if case let .retry(attempts) = retryInfo {
                numAttempts = attempts
            }
            return .run { [numAttempts] send in
                let networkSesion = await klaviyoSwiftEnvironment.networkSession()
                let result = await environment.klaviyoAPI.send(networkSesion, request, numAttempts)
                switch result {
                case let .success(data):
                    do {
                        switch request.endpoint {
                        case .fetchForms:
                            let formsResponse = try JSONDecoder().decode(FullFormsResponse.self, from: data)
                            await send(.handleFormsResponse(formsResponse))
                        default:
                            break
                        }
                    } catch let error as DecodingError {
                        environment.logger.error("Error decoding JSON response: \(error.localizedDescription)")
                    } catch {
                        environment.logger.error("An unexpected error occurred: \(error.localizedDescription)")
                    }

                    await send(.deQueueCompletedResults(request))
                case let .failure(error):
                    await send(handleRequestError(request: request, error: error, retryInfo: retryInfo))
                }
            } catch: { error, send in
                // For now assuming this is cancellation since nothing else can throw AFAICT
                environment.logger.error("Unknown error thrown during request processing \(error)")
                await send(.cancelInFlightRequests)
            }.cancellable(id: CancelIds.request)

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
                return Effect.cancel(id: CancelIds.request)
                    .concatenate(with: Effect.cancel(id: CancelIds.timer))
                    .concatenate(with: .send(.cancelInFlightRequests))
            case .reachableViaWiFi:
                state.flushInterval = StateManagementConstants.wifiFlushInterval
            case .reachableViaWWAN:
                state.flushInterval = StateManagementConstants.cellularFlushInterval
            }
            let flushInterval = state.flushInterval
            return .run { send in
                for await _ in environment.timer(flushInterval) {
                    await send(KlaviyoAction.flushQueue(environment.appContextInfo()))
                }
            }
            .cancellable(id: CancelIds.timer, cancelInFlight: true)

        case let .requestFailed(request, retryInfo):
            var exceededRetries = false
            switch retryInfo {
            case let .retry(count):
                exceededRetries = count > ErrorHandlingConstants.maxRetries
                state.retryInfo = .retry(exceededRetries ? 1 : count)
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

        case .enqueueEvent(var event, let appContextInfo):
            guard case .initialized = state.initalizationState,
                  let apiKey = state.apiKey,
                  let anonymousId = state.anonymousId
            else {
                state.pendingRequests.append(.event(event, appContextInfo))
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
                    pushToken: state.pushTokenData?.pushToken,
                    appContextInfo: appContextInfo))

            let endpoint = KlaviyoEndpoint.createEvent(payload)
            let request = KlaviyoRequest(apiKey: apiKey, endpoint: endpoint, uuid: environment.uuid().uuidString)
            state.enqueueRequest(request: request)

            /*
             if we receive an opened push event we want to flush the queue right away so that
             we don't miss any user engagement events. In all other cases we will flush the queue
             using the flush intervals defined above in `StateManagementConstants`
             */
            return event.metric.name == ._openedPush ? .send(.flushQueue(appContextInfo)) : .none

        case let .enqueueProfile(profile, appContextInfo):
            guard case .initialized = state.initalizationState
            else {
                state.pendingRequests.append(.profile(profile, appContextInfo))
                return .none
            }

            let pushTokenData = state.pushTokenData
            state.reset(preserveTokenData: false, appContextInfo: appContextInfo)
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
                anonymousId: anonymousId)

            if let tokenData = pushTokenData {
                let payload = PushTokenPayload(
                    pushToken: tokenData.pushToken,
                    enablement: tokenData.pushEnablement.rawValue,
                    background: tokenData.pushBackground.rawValue,
                    profile: profilePayload, appContextInfo: appContextInfo)
                request = KlaviyoRequest(
                    apiKey: apiKey,
                    endpoint: .registerPushToken(payload), uuid: environment.uuid().uuidString)
            } else {
                request = KlaviyoRequest(
                    apiKey: apiKey,
                    endpoint: .createProfile(CreateProfilePayload(data: profilePayload)), uuid: environment.uuid().uuidString)
            }
            state.enqueueRequest(request: request)

            return .none

        case let .setBadgeCount(count):
            return .run { _ in
                _ = await klaviyoSwiftEnvironment.setBadgeCount(count)
            }

        case let .resetProfile(appContextInfo):
            guard case .initialized = state.initalizationState
            else {
                return .none
            }
            state.reset(appContextInfo: appContextInfo)
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

            return .send(.deQueueCompletedResults(request))

        case .fetchForms:
            guard case .initialized = state.initalizationState,
                  let apiKey = state.apiKey
            else {
                return .none
            }

            let request = KlaviyoRequest(apiKey: apiKey, endpoint: .fetchForms, uuid: environment.uuid().uuidString)
            state.enqueueRequest(request: request)

            return .none

        case let .handleFormsResponse(fullFormsResponse):
            guard let firstForm = fullFormsResponse.fullForms.first else { return .none }

            // TODO: handle the form data
            // example: Update the state to display the form
            // state.firstForm = firstForm
            //
            // for now, prettyprint to console
            // (TODO: remove this debug code after we've handled the response appropriately!)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            do {
                let data = try encoder.encode(fullFormsResponse)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            } catch {
                print("Failed to encode and pretty-print JSON: \(error)")
            }

            return .none
        }
    }
}

extension Store where State == KlaviyoState, Action == KlaviyoAction {
    static let production = Store(initialState: KlaviyoState(queue: [])) {
        KlaviyoReducer()
    }
}

extension Event {
    func updateEventWithState(state: inout KlaviyoState) -> Event {
        let identifiers = Identifiers(
            email: state.email,
            phoneNumber: state.phoneNumber,
            externalId: state.externalId)
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
