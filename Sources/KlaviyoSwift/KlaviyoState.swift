//
//  KlaviyoState.swift
//  
//
//  Created by Noah Durell on 12/1/22.
//

import Foundation

struct KlaviyoState: Equatable, Codable {
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
    var flushInterval = 10.0
}

// MARK: Klaviyo state persistence

private func klaviyoStateFile(apiKey: String) -> URL {
    let fileName = "klaviyo-\(apiKey)-state.json"
    let directory = environment.fileClient.libraryDirectory()
    return directory.appendingPathComponent(fileName, isDirectory: false)
}

func storeKlaviyoState(state: KlaviyoState, file: URL) {
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

func loadKlaviyoStateFromDisk(apiKey: String) -> KlaviyoState {
    let fileName = klaviyoStateFile(apiKey: apiKey)
    guard environment.fileClient.fileExists(fileName.path) else {
        return migrateLegacyDataToKlaviyoState(with: apiKey, to: fileName)
 
    }
    guard let stateData = try? environment.data(fileName) else {
        environment.logger.error("Klaviyo state file invalid starting from scratch.")
        removeStateFile(at: fileName)
        return createAndStoreInitialState(with: apiKey, at: fileName)
    }
    guard let decodedState = try? environment.analytics.decodeJSON(stateData),
            let state = decodedState.value as? KlaviyoState else {
        environment.logger.error("Unable to decode existing state file.")
        removeStateFile(at: fileName)
        return createAndStoreInitialState(with: apiKey, at: fileName)
    }
    return state
}

private func createAndStoreInitialState(with apiKey: String, at file: URL) -> KlaviyoState {
    let anonymousId = environment.analytics.uuid().uuidString
    let state = KlaviyoState(apiKey: apiKey, anonymousId: anonymousId, queue: [], requestsInFlight: [])
    storeKlaviyoState(state: state, file: file)
    return state
}

// MARK: Klaviyo State Legacy Migration
// It's unclear how long this should live for but it'll probably here for a while.

private func migrateLegacyDataToKlaviyoState(with apiKey: String, to file: URL) -> KlaviyoState {
    // Read data from user defaults external id, email, push token
    // Read old events and people data
    // Remove old keys and data from userdefaults and files
    // return populated KlaviyoState
    let email = environment.getUserDefaultString("$kl_email")
    let anonymousId = environment.analytics.uuid().uuidString
    let externalId = environment.getUserDefaultString("kl_customerID")
    var state = KlaviyoState(apiKey: apiKey,
                             email: email,
                             anonymousId: anonymousId,
                             externalId: externalId,
                             queue: [],
                             requestsInFlight: [])
    state.queue = readLegacyRequestData(with: apiKey, from: state)
    let file = klaviyoStateFile(apiKey: apiKey)
    storeKlaviyoState(state: state, file: file)
    return state
}

private func readLegacyRequestData(with apiKey: String, from state: KlaviyoState) -> [KlaviyoAPI.KlaviyoRequest] {
    var queue = [KlaviyoAPI.KlaviyoRequest]()
    let eventsFileURL = filePathForData(apiKey: apiKey, data: "events")
    if let eventsData = unarchiveFromFile(fileURL: eventsFileURL) {
        for possibleEvent in eventsData {
            guard let event = possibleEvent as? NSDictionary,
                    let eventName = event["event"] as? String else {
                continue
            }
            let customerProperties = event["customer_properties"] as? NSDictionary
            let properties = event["properties"] as? NSDictionary
            let legacyEvent = LegacyEvent(eventName: eventName,
                                                          customerProperties: customerProperties,
                                                          properties: properties)
            guard let request = try? legacyEvent.buildEventRequest(with: apiKey) else {
                continue
            }
            queue.append(request)
        }
    }

    let profileFileURL = filePathForData(apiKey: apiKey, data: "people")
    if let profileData = unarchiveFromFile(fileURL: profileFileURL) {
        for possibleProfile in profileData {
            guard let profile = possibleProfile as? NSDictionary else {
                continue
            }
            guard let customerProperties = profile["properties"] as? NSDictionary else {
                continue
            }
            let legacyProfile = LegacyProfile(customerProperties: customerProperties)
            guard let request = try? legacyProfile.buildProfileRequest(with: apiKey, from: state) else {
                continue
            }
            queue.append(request)
        }
    }
    return queue
}
