//
//  KlaviyoState.swift
//  
//
//  Created by Noah Durell on 11/28/22.
//

import Foundation

/**
State and Actions to be used with the Store.
 
 */

struct KlaviyoState: Encodable {
    var apiKey: String?
    var email: String?
    var anonymousId: String?
    var phoneNumber: String?
    var externalId: String?
    var pushToken: String?
    var queue: [KlaviyoAPI.KlaviyoRequest]
    var requestsInFlight: [KlaviyoAPI.KlaviyoRequest]
    var initialized = false
    var flushing = false

    func buildProfileTask(properties: [String: Any] = [:]) -> EffectTask<KlaviyoAction> {
        return .task {
            guard let anonymousId = anonymousId else {
                throw KlaviyoAPI.KlaviyoAPIError.internalError("missing anonymous id key")
            }
            let payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload(data: .init(profile: .init(attributes: .init(email: email, phoneNumber: phoneNumber, externalId: externalId, properties: properties)), anonymousId: anonymousId))
            let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.createProfile(payload)
            guard let apiKey = apiKey else {
                throw KlaviyoAPI.KlaviyoAPIError.internalError("missing api key")
            }
            return .enqueueRequest(KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint))
        }
    }
}

enum KlaviyoAction {
    case initialize(String?)
    case setEmail(String)
    case setAnonymousId(String)
    case setPhoneNumber(String)
    case setExternalId(String)
    case setPushToken(String)
    case enqueueRequest(KlaviyoAPI.KlaviyoRequest)
    case dequeCompletedResults(KlaviyoAPI.KlaviyoRequest)
    case flushQueue
    case sendRequest
    case stop
    case start
    case cancelInFlightRequests
}

/// Description: Reducer for our store.
/// - Parameters:
///   - state: current state to be reduced.
///   - action: action to reduce state.
/// - Returns: Effect which run side effecty code and may further produce action to update state.
func reduce(state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> {
    switch action {
    case let .initialize(apiKey):
        state.apiKey = apiKey
        // TODO: read from disk and initialize queue
        return .run { send in
            
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
        return .none
    case .enqueueRequest(let request):
        state.queue.append(request)
        return .none
    case .flushQueue:
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
        // TODO: stop timer, cancel in flight requests, then persist to disk.
        return .run { send in
            await send(.cancelInFlightRequests)
        }
    case .start:
        // TODO: start timer
        return .none
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
        guard let request = state.requestsInFlight.first else {
            return .none
        }
        return .run { send in
            let result = try await withCheckedThrowingContinuation({
                (continuation: CheckedContinuation<Result<Data, KlaviyoAPI.KlaviyoAPIError>, Error>) in
                environment.analytics.klaviyoAPI.sendRequest(request) { result in
                    continuation.resume(returning: result)
                }
            })
            switch result {
                
            case .success(_):
                // may want to inspect response further.
                await send(.dequeCompletedResults(request))
            case .failure(_):
                // depending on failure may want to deque
                await send(.cancelInFlightRequests)
            }
            
        }
    case .cancelInFlightRequests:
        state.flushing = false
        state.queue.insert(contentsOf: state.requestsInFlight, at: 0)
        state.requestsInFlight = []
        return .none
    }
}

extension Store {
    public static let production = Store(state: .init(queue: [], requestsInFlight: []), reducer: reduce(state:action:)) 
}
