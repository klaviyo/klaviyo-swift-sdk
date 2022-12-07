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
let CELLULAR_FLUSH_INTERVAL = 10.0
let WIFI_FLUSH_INTERVAL = 30.0

enum KlaviyoAction: Equatable {
    case initialize(String)
    case completeInitialization(KlaviyoState)
    case setEmail(String)
    case setAnonymousId(String)
    case setPhoneNumber(String)
    case setExternalId(String)
    case setPushToken(String)
    case enqueueRequest(KlaviyoAPI.KlaviyoRequest)
    case dequeCompletedResults(KlaviyoAPI.KlaviyoRequest)
    case networkConnectivityChanged(Reachability.NetworkStatus)
    case flushQueue
    case sendRequest
    case stop
    case start
    case cancelInFlightRequests
}

struct RequestId {}
struct FlushTimer {}

struct KlaviyoReducer: ReducerProtocol {
    typealias State = KlaviyoState
    typealias Action = KlaviyoAction
    func reduce(into state: inout KlaviyoSwift.KlaviyoState, action: KlaviyoSwift.KlaviyoAction) -> EffectTask<KlaviyoSwift.KlaviyoAction> {
        switch action {
        case let .initialize(apiKey):
            state.apiKey = apiKey
            return .run { send in
                let initialState = loadKlaviyoStateFromDisk(apiKey: apiKey)
                await send(.completeInitialization(initialState))
            }
        case var .completeInitialization(initialState):
            let queuedRequests = state.queue
            initialState.queue += queuedRequests
            initialState.initialized = true
            state = initialState
            return .run { [state] send in
                await send(.enqueueRequest(try state.buildProfileRequest()))
                await send(.start)
            }
        case .setEmail(let email):
            state.email = email
            return state.buildProfileTask()
        case .setAnonymousId(let anonymousId):
            state.anonymousId = anonymousId
            return state.buildProfileTask()
        case .setPhoneNumber(let phoneNumber):
            state.phoneNumber = phoneNumber
            return state.buildProfileTask()
        case .setExternalId(let externalId):
            state.externalId = externalId
            return state.buildProfileTask()
        case .setPushToken(let pushToken):
            state.pushToken = pushToken
            return .task { [state] in
                return .enqueueRequest(try state.buildTokenRequest())
            }
        case .enqueueRequest(let request):
            state.queue.append(request)
            return .none
        case .flushQueue:
            guard state.initialized else {
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
            return EffectPublisher.cancel(ids: [RequestId.self, FlushTimer.self])
                .map { KlaviyoAction.cancelInFlightRequests }
                .concatenate(with: .run(operation: { _ in
                    // TODO: Save to disk here...
                }))
        case .start:
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
            guard state.initialized else {
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
                    // may want to inspect response further.
                    await send(.dequeCompletedResults(request))
                case .failure(_):
                    // depending on failure may want to deque
                    await send(KlaviyoAction.cancelInFlightRequests)
                }
            }.cancellable(id: RequestId.self)
        case .cancelInFlightRequests:
            state.flushing = false
            state.queue.insert(contentsOf: state.requestsInFlight, at: 0)
            state.requestsInFlight = []
            return .none
        case .networkConnectivityChanged(let networkStatus):
            switch networkStatus {
            case .notReachable:
                state.flushInterval = 0
                return EffectPublisher.cancel(ids: [RequestId.self, Timer.self])
                    .map { KlaviyoAction.cancelInFlightRequests }
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
    
    func buildProfileTask(properties: [String: Any] = [:]) -> EffectTask<KlaviyoAction> {
        return .task {
            return .enqueueRequest(try self.buildProfileRequest(properties: properties))
        }
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
