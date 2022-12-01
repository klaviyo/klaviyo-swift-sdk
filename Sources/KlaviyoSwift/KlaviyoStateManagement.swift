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
    case initialize(String)
    case completeInitialization(KlaviyoState)
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
            let initialState = loadKlaviyoStateFromDisk(apiKey: apiKey)
            await send(.completeInitialization(initialState))
        }
    case var .completeInitialization(initialState):
        let queuedRequests = state.queue
        initialState.queue += queuedRequests
        state = initialState
        return .task {
            .start
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

private func klaviyoStateFile(apiKey: String) -> URL {
    let fileName = "klaviyo-\(apiKey)-state.json"
    let directory = environment.fileClient.libraryDirectory()
    return directory.appendingPathComponent(fileName, isDirectory: false)
}

private func loadKlaviyoStateFromDisk(apiKey: String) -> KlaviyoState {
    let fileName = klaviyoStateFile(apiKey: apiKey)
    guard environment.fileClient.fileExists(fileName.path) else {
        return migrateLegacyDataToKlaviyoState(with: apiKey, to: fileName)
 
    }
    guard let stateData = try? environment.data(fileName) else {
        environment.logger.error("Klaviyo state file invalid starting from scratch.")
        removeStateFile(at: fileName)
        return createAndStoreInitialState(with: apiKey, at: fileName)
    }
    // Check if new state file exists
    // If not migrate existing data to new state file
    // also create new anonymous id
    // then return state with migrated data
    // otherwise read existing state file and return it
    guard let decodedState = try? environment.decodeJSON(stateData),
            let state = decodedState.value as? KlaviyoState else {
        environment.logger.error("Unable to decode existing state file.")
        removeStateFile(at: fileName)
        return createAndStoreInitialState(with: apiKey, at: fileName)
    }
    return state
}

private func migrateLegacyDataToKlaviyoState(with apiKey: String, to file: URL) -> KlaviyoState {
    // Read data from user defaults external id, email, push token
    // Read old events and people data
    // Remove old keys and data from userdefaults and files
    // return populated KlaviyoState
    let email = environment.analytics.getUserDefaultStringValue("$kl_email")
    let anonymousId = environment.analytics.uuid().uuidString
    let externalId = environment.analytics.getUserDefaultStringValue("kl_customerID")
    let requests = readLegacyRequestData(with: apiKey, for: anonymousId)
    let state = KlaviyoState(apiKey: apiKey, email: email, anonymousId: anonymousId, externalId: externalId, queue: [], requestsInFlight: [])
    storeKlaviyoState(state: state, at: file)
    return state
}

private func readLegacyRequestData(with apiKey: String, for anonymousId: String) -> [KlaviyoAPI.KlaviyoRequest] {
    var queue = [KlaviyoAPI.KlaviyoRequest]()
    let eventsFileURL = filePathForData(apiKey: apiKey, data: "events")
    if let eventsData = unarchiveFromFile(fileURL: eventsFileURL) {
        for possibleEvent in eventsData {
            guard let event = possibleEvent as? NSDictionary, let eventName = event["event"] as? String else {
                continue
            }
            let customerProperties = event["customer_properties"] as? NSDictionary
            let properties = event["properties"] as? NSDictionary
            let legacyEvent = AnalyticsEngine.LegacyEvent(eventName: eventName,
                                                          customerProperties: customerProperties,
                                                          properties: properties)
            guard let request = try? legacyEvent.buildEventRequest(with: apiKey) else {
                continue
            }
            queue.append(request)
        }
    }
    let profileFileURL = filePathForData(apiKey: apiKey, data: "people")
    if let profileData = unarchiveFromFile(fileURL: eventsFileURL) {
        for possibleProfile in profileData {
            guard let profile = possibleProfile as? NSDictionary else {
                continue
            }
            let customerProperties = profile["properties"] as? NSDictionary ?? NSDictionary()
            let legacyProfile = AnalyticsEngine.LegacyProfile(customerProperties: customerProperties)
            guard let request = try? legacyProfile.buildProfileRequest(with: apiKey, for: anonymousId) else {
                continue
            }
            queue.append(request)
        }
    }
    return queue
}

private func createAndStoreInitialState(with apiKey: String, at file: URL) -> KlaviyoState {
    let anonymousId = environment.analytics.uuid().uuidString
    let state = KlaviyoState(apiKey: apiKey, anonymousId: anonymousId, queue: [], requestsInFlight: [])
    storeKlaviyoState(state: state, at: file)
    return state
}

private func storeKlaviyoState(state: KlaviyoState, at file: URL) {
    do {
        try environment.fileClient.write(environment.analytics.encodeJSON(state), file)
    } catch {
        environment.logger.error("Unable to save klaviyo state.")
    }
}

private func removeStateFile(at file: URL) {
    do {
        try environment.fileClient.removeItem(file.path)
    } catch {
        environment.logger.error("Unable to remove state file.")
    }
}

private func eventsFilePath(with apiKey: String) -> URL? {
    return filePathForData(apiKey: apiKey, data: "events")
}

private func peopleFilePath(with apiKey: String) -> URL? {
    return filePathForData(apiKey: apiKey, data: "people")
}

