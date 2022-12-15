//
//  StateManagement.swift
//  
//
//  Created by Noah Durell on 12/6/22.
//

import Foundation

/**

 Actions and reducers related to klaviyo state.
 
 */

// Request flush interval in seconds.
let CELLULAR_FLUSH_INTERVAL = 30.0
let WIFI_FLUSH_INTERVAL = 10.0

enum KlaviyoAction: Equatable {
    case initialize(String)
    case completeInitialization(KlaviyoState)
    case setEmail(String)
    case setAnonymousId(String)
    case setPhoneNumber(String)
    case setExternalId(String)
    case setPushToken(String)
    case dequeCompletedResults(KlaviyoAPI.KlaviyoRequest)
    case networkConnectivityChanged(Reachability.NetworkStatus)
    case flushQueue
    case sendRequest
    case stop
    case start
    case cancelInFlightRequests
    case archiveCurrentState
    case enqueueLegacyEvent(LegacyEvent)
    case enqueueLegacyProfile(LegacyProfile)
}

struct RequestId {}
struct FlushTimer {}
struct AppLifeCycle {}

struct KlaviyoReducer: ReducerProtocol {
    typealias State = KlaviyoState
    typealias Action = KlaviyoAction
    func reduce(into state: inout KlaviyoSwift.KlaviyoState, action: KlaviyoSwift.KlaviyoAction) -> EffectTask<KlaviyoSwift.KlaviyoAction> {
        switch action {
        case let .initialize(apiKey):
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
            let queuedRequests = state.queue
            initialState.queue += queuedRequests

            state = initialState
            state.initalizationState = .initialized
            if let request = try? state.buildProfileRequest() {
                state.queue.append(request)
            }
            return .task {
                .start
            }.merge(with: environment.appLifeCycle.lifeCycleEvents().eraseToEffect())
        case .setEmail(let email):
            guard case .initialized = state.initalizationState else {
                return .none
            }
            // We could move this linebefore initialization...
            // once the sdk initialized it would send the email.
            state.email = email
            
            guard let request = try? state.buildProfileRequest() else {
                return .none
            }
            state.queue.append(request)
            return .none
        case .setAnonymousId(let anonymousId):
            guard case .initialized = state.initalizationState else {
                return .none
            }
            state.anonymousId = anonymousId
            
            guard let request = try? state.buildProfileRequest() else {
                return .none
            }
            state.queue.append(request)
            return .none
        case .setPhoneNumber(let phoneNumber):
            guard case .initialized = state.initalizationState else {
                return .none
            }
            state.phoneNumber = phoneNumber
            
            guard let request = try? state.buildProfileRequest() else {
                return .none
            }
            state.queue.append(request)
            return .none
        case .setExternalId(let externalId):
            guard case .initialized = state.initalizationState else {
                return .none
            }
            state.externalId = externalId
            
            guard let request = try? state.buildProfileRequest() else {
                return .none
            }
            state.queue.append(request)
            return .none
        case .setPushToken(let pushToken):
            guard case .initialized = state.initalizationState else {
                return .none
            }
            state.pushToken = pushToken
            guard let request = try? state.buildTokenRequest() else {
                return .none
            }
            state.queue.append(request)
            return .none
        case .flushQueue:
            guard case .initialized = state.initalizationState else {
                return .none
            }
            if state.flushing {
                return .none
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
                    await send(.archiveCurrentState)
                }))
        case .start:
            guard case .initialized = state.initalizationState else {
                return .none
            }
            return environment.analytics.timer(state.flushInterval)
                    .map { _ in
                        KlaviyoAction.flushQueue
                    }.eraseToEffect()
                    .cancellable(id: Timer.self, cancelInFlight: true)
        case .dequeCompletedResults(let completedRequest):
            state.requestsInFlight.removeAll { inflightRequest in
                completedRequest.uuid == inflightRequest.uuid
            }
            if state.requestsInFlight.isEmpty {
                state.flushing = false
                return .none
            }
            return .task { .sendRequest }
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
            return .run { send in
                let result = await environment.analytics.klaviyoAPI.send(request)
                switch result {
                case .success(_):
                    // TODO: may want to inspect response further.
                    await send(.dequeCompletedResults(request))
                case .failure(let error):
                    switch error {
                    case let .httpError(statuscode, data):
                        runtimeWarn("An http error occured status code: \(statuscode) data: \(data)")
                        await send(.dequeCompletedResults(request))
                    case .networkError(_):
                        runtimeWarn("A network error occurred: \(error)")
                        await send(KlaviyoAction.cancelInFlightRequests)
                    case .internalError(let data):
                        runtimeWarn("An internal error occurred msg: \(data)")
                        await send(.dequeCompletedResults(request))
                    case .internalRequestError(let error):
                        runtimeWarn("An internal request error occurred msg: \(error)")
                        await send(.dequeCompletedResults(request))
                    case .unknownError(let error):
                        runtimeWarn("An unknown request error occured \(error)")
                        await send(.dequeCompletedResults(request))
                    case .dataEncodingError:
                        runtimeWarn("A data encoding error occurred during transmission.")
                        await send(.dequeCompletedResults(request))
                    case .invalidData:
                        runtimeWarn("Invalid data supplied for request. Skipping.")
                        await send(.dequeCompletedResults(request))
                    case .rateLimitError:
                        // not currently thrown may want to get rid of this.
                        await send(KlaviyoAction.cancelInFlightRequests)
                    case .missingOrInvalidResponse:
                        runtimeWarn("Missing or invalid response from api.")
                        await send(.dequeCompletedResults(request))
                    }
                    
                }
            } catch: { error, send in
                // TODO: Determine if we can differentiate between cancellation and errors that should be dequeued
                runtimeWarn("Unknown error thrown during request processing \(error)")
                await send(.cancelInFlightRequests)
            }.cancellable(id: RequestId.self)
        case .cancelInFlightRequests:
            state.flushing = false
            state.queue.insert(contentsOf: state.requestsInFlight, at: 0)
            state.requestsInFlight = []
            return .none
        case .networkConnectivityChanged(let networkStatus):
            guard case .initialized = state.initalizationState else {
                return .none
            }
            switch networkStatus {
            case .notReachable:
                state.flushInterval = 0
                return EffectPublisher.cancel(ids: [RequestId.self, Timer.self])
                    .concatenate(with: .run { send in
                        await send(.cancelInFlightRequests)
                    })
            case .reachableViaWiFi:
                state.flushInterval = WIFI_FLUSH_INTERVAL
            case .reachableViaWWAN:
                state.flushInterval = CELLULAR_FLUSH_INTERVAL
            }
            return environment.analytics.timer(state.flushInterval)
                    .map { _ in
                        KlaviyoAction.flushQueue
                    }.eraseToEffect()
                    .cancellable(id: Timer.self, cancelInFlight: true)
        case .archiveCurrentState:
            guard case .initialized = state.initalizationState else {
                return .none
            }
            return .run { [state] _ in
                saveKlaviyoState(state: state)
            }
 
        case .enqueueLegacyEvent(let legacyEvent):
            // TODO: Needs a few tests.
            guard case .initialized = state.initalizationState, let apiKey = state.apiKey else {
                return .none
            }
            
            guard let identifiers = legacyEvent.identifiers else {
                return .none
            }
            state.email = identifiers.email ?? state.email
            state.anonymousId = identifiers.anonymousId ?? state.anonymousId
            state.phoneNumber = identifiers.phoneNumber ?? state.phoneNumber
            state.externalId = identifiers.externalId ?? state.externalId
            guard let request = try? legacyEvent.buildEventRequest(with: apiKey, from: state) else {
                return .none
            }
            state.queue.append(request)
            return .none
        case .enqueueLegacyProfile(let legacyProfile):
            guard case .initialized = state.initalizationState, let apiKey = state.apiKey else {
                return .none
            }
            guard let identifiers = legacyProfile.identifiers else {
                return .none
            }
            state.email = identifiers.email ?? state.email
            state.anonymousId = identifiers.anonymousId ?? state.anonymousId
            state.phoneNumber = identifiers.phoneNumber ?? state.phoneNumber
            state.externalId = identifiers.externalId ?? state.externalId
            guard let request = try? legacyProfile.buildProfileRequest(with: apiKey, from: state) else {
                return .none
            }
            state.queue.append(request)
            return .none
        }
    }
}

extension Store where State == KlaviyoState, Action == KlaviyoAction {
    static let production = Store(initialState: KlaviyoState(queue: [], requestsInFlight: []),
                                  reducer: KlaviyoReducer())
}

extension KlaviyoState {
    func buildProfileRequest(properties: [String: Any] = [:]) throws -> KlaviyoAPI.KlaviyoRequest {
        guard let anonymousId = anonymousId else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("missing anonymous id key")
        }
        let payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload(
            data: .init(
                profile: .init(attributes: .init(
                    email: email,
                    phoneNumber: phoneNumber,
                                            externalId: externalId,
                                            properties: properties)
                ),
                anonymousId: anonymousId)
        )
        let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.createProfile(payload)
        guard let apiKey = apiKey else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("missing api key")
        }
        return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
    }
    
    func buildTokenRequest() throws -> KlaviyoAPI.KlaviyoRequest {
        guard let apiKey = apiKey else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("missing api key")
        }
        guard let anonymousId = anonymousId else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("missing anonymous id key")
        }
        guard let token = pushToken else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("missing push token")
        }
        let payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload(
            token: apiKey,
            properties: .init(anonymousId: anonymousId,
                              pushToken: token,
                              email: email,
                              phoneNumber: phoneNumber,
                              externalId: externalId)
        )
        let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.storePushToken(payload)
        return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
    }
}
