//
//  KlaviyoState.swift
//  
//
//  Created by Noah Durell on 12/1/22.
//

import Foundation
import UIKit
import AnyCodable

struct KlaviyoState: Equatable, Codable {
    enum InitializationSate: Equatable {
        case uninitialized
        case initializing
        case initialized
    }
    enum PendingRequest: Equatable {
        case legacyEvent(LegacyEvent)
        case legacyProfile(LegacyProfile)
        case event(Event)
        case profile(Profile)
    }
    var apiKey: String?
    var email: String?
    var anonymousId: String?
    var phoneNumber: String?
    var externalId: String?
    var pushToken: String?
    var queue: [KlaviyoAPI.KlaviyoRequest]
    var requestsInFlight: [KlaviyoAPI.KlaviyoRequest] = []
    var initalizationState = InitializationSate.uninitialized
    var flushing = false
    var flushInterval = 10.0
    var retryInfo = RetryInfo.retry(0)
    var pendingRequests: [PendingRequest] = []
    
    enum CodingKeys: CodingKey {
        case apiKey
        case email
        case anonymousId
        case phoneNumber
        case externalId
        case pushToken
        case queue
    }
    
    mutating func enqueueRequest(request: KlaviyoAPI.KlaviyoRequest) {
        guard queue.count + 1 < MAX_QUEUE_SIZE else {
            return
        }
        queue.append(request)
    }
    
    mutating func enqueueProfileRequest() {
        guard let request = try? self.buildProfileRequest() else {
            return
        }
        queue.append(request)
    }
    
    mutating func updateStateWithLegacyIdentifiers(identifiers: LegacyIdentifiers) {
        email = identifiers.email ?? email
        phoneNumber = identifiers.phoneNumber ?? phoneNumber
        externalId = identifiers.externalId ?? externalId
    }
}

// MARK: Klaviyo state persistence

func saveKlaviyoState(state: KlaviyoState) {
    guard let apiKey = state.apiKey else {
        environment.logger.error("Attempt to save state without an api key.")
        return
    }
    let file = klaviyoStateFile(apiKey: apiKey)
    storeKlaviyoState(state: state, file: file)
}

private func klaviyoStateFile(apiKey: String) -> URL {
    let fileName = "klaviyo-\(apiKey)-state.json"
    let directory = environment.fileClient.libraryDirectory()
    return directory.appendingPathComponent(fileName, isDirectory: false)
}

private func storeKlaviyoState(state: KlaviyoState, file: URL) {
    do {
        try environment.fileClient.write(environment.analytics.encodeJSON(AnyEncodable(state)), file)
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
        if needsMigration(with: apiKey) {
            return migrateLegacyDataToKlaviyoState(with: apiKey, to: fileName)
        }
        return createAndStoreInitialState(with: apiKey, at: fileName)
 
    }
    guard let stateData = try? environment.data(fileName) else {
        environment.logger.error("Klaviyo state file invalid starting from scratch.")
        removeStateFile(at: fileName)
        return createAndStoreInitialState(with: apiKey, at: fileName)
    }
    guard var state: KlaviyoState = try? environment.analytics.decoder.decode(stateData) else {
        environment.logger.error("Unable to decode existing state file. Removing.")
        removeStateFile(at: fileName)
        return createAndStoreInitialState(with: apiKey, at: fileName)
    }
    if state.apiKey != apiKey {
        // Clear existing stat since we are using a new api state.
        state = KlaviyoState(apiKey: apiKey, anonymousId: environment.analytics.uuid().uuidString, queue: [])
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
    let anonymousId = environment.legacyIdentifier()
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

private func needsMigration(with apiKey: String) -> Bool {
    let email = environment.getUserDefaultString("$kl_email")
    let externalId = environment.getUserDefaultString("kl_customerID")
    let eventsFileURL = filePathForData(apiKey: apiKey, data: "events")
    let eventsFileExists =  environment.fileClient.fileExists(eventsFileURL.path)
    let profileFileURL = filePathForData(apiKey: apiKey, data: "people")
    let profilesFileExists = environment.fileClient.fileExists(profileFileURL.path)
    return email != nil || externalId != nil || eventsFileExists || profilesFileExists
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
            guard let request = try? legacyEvent.buildEventRequest(with: apiKey, from: state) else {
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
