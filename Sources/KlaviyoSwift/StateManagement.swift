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
    case enqueueRequest(KlaviyoAPI.KlaviyoRequest)
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

struct KlaviyoReducer: ReducerProtocol {
    typealias State = KlaviyoState
    typealias Action = KlaviyoAction
    func reduce(into state: inout KlaviyoSwift.KlaviyoState, action: KlaviyoSwift.KlaviyoAction) -> EffectTask<KlaviyoSwift.KlaviyoAction> {
        switch action {
        case let .initialize(apiKey):
            if state.initialized {
                return .none
            }
            state.apiKey = apiKey
            return .run { send in
                let initialState = loadKlaviyoStateFromDisk(apiKey: apiKey)
                await send(.completeInitialization(initialState))
            }
        case var .completeInitialization(initialState):
            if state.initialized {
                return .none
            }
            let queuedRequests = state.queue
            initialState.queue += queuedRequests
            initialState.initialized = true
            state = initialState
            return .run { [state] send in
                await send(.enqueueRequest(try state.buildProfileRequest()))
                await send(.start)
            }
        case .setEmail(let email):
            guard state.initialized else {
                return .none
            }
            state.email = email
            return state.buildProfileTask()
        case .setAnonymousId(let anonymousId):
            guard state.initialized else {
                return .none
            }
            state.anonymousId = anonymousId
            return state.buildProfileTask()
        case .setPhoneNumber(let phoneNumber):
            guard state.initialized else {
                return .none
            }
            state.phoneNumber = phoneNumber
            return state.buildProfileTask()
        case .setExternalId(let externalId):
            guard state.initialized else {
                return .none
            }
            state.externalId = externalId
            return state.buildProfileTask()
        case .setPushToken(let pushToken):
            guard state.initialized else {
                return .none
            }
            // TODO: check if we already have this token, skip sending if we do.
            state.pushToken = pushToken
            return .task { [state] in
                return .enqueueRequest(try state.buildTokenRequest())
            }
        case .enqueueRequest(let request):
            guard state.initialized else {
                return .none
            }
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
            guard state.initialized else {
                return .none
            }
            return EffectPublisher.cancel(ids: [RequestId.self, FlushTimer.self])
                .concatenate(with: .run(operation: { send in
                    await send(.cancelInFlightRequests)
                    await send(.archiveCurrentState)
                }))
        case .start:
            guard state.initialized else {
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
                    // TODO: may want to inspect response further.
                    await send(.dequeCompletedResults(request))
                case .failure(_):
                    // TODO: depending on failure may want to deque
                    await send(KlaviyoAction.cancelInFlightRequests)
                }
            } catch: { _, _ in
                environment.logger.error("request error")
                // TODO: maybe better handling here...
            }.cancellable(id: RequestId.self)
        case .cancelInFlightRequests:
            state.flushing = false
            state.queue.insert(contentsOf: state.requestsInFlight, at: 0)
            state.requestsInFlight = []
            return .none
        case .networkConnectivityChanged(let networkStatus):
            guard state.initialized else {
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
            guard state.initialized else {
                return .none
            }
            return .run { [state] _ in
                saveKlaviyoState(state: state)
            }
 
        case .enqueueLegacyEvent(let legacyEvent):
            // TODO: Needs a few tests.
            guard let apiKey = state.apiKey else {
                return .none
            }
            // TODO: might need to update state based on data in here.
            return .run { [state] send in
                guard let request = try? legacyEvent.buildEventRequest(with: apiKey, from: state) else {
                    return
                }
                await send(.enqueueRequest(request))
            }
        case .enqueueLegacyProfile(let legacyProfile):
            // TODO: Needs a few tests.
            guard let apiKey = state.apiKey else {
                return .none
            }
            // TODO: might need to update state based on data in here.
            return .run { [state] send in
                guard let request = try? legacyProfile.buildProfileRequest(with: apiKey, from: state) else {
                    return
                }
                await send(.enqueueRequest(request))
            }
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
