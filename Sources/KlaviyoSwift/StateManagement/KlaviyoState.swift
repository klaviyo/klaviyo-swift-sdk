//
//  KlaviyoState.swift
//
//
//  Created by Noah Durell on 12/1/22.
//

import Foundation
import KlaviyoCore
import KlaviyoSDKDependencies
import UIKit

typealias DeviceMetadata = PushTokenPayload.PushToken.Attributes.MetaData

struct KlaviyoState: Equatable, Codable, Sendable {
    enum InitializationState: Equatable, Codable, Sendable {
        case uninitialized
        case initializing
        case initialized
    }

    enum PendingRequest: Equatable, Sendable {
        case event(Event, AppContextInfo)
        case profile(Profile, AppContextInfo)
        case pushToken(String, PushEnablement, PushBackground, AppContextInfo)
        case setEmail(String, AppContextInfo)
        case setExternalId(String, AppContextInfo)
        case setPhoneNumber(String, AppContextInfo)
    }

    struct PushTokenData: Equatable, Codable, Sendable {
        var pushToken: String
        var pushEnablement: PushEnablement
        var pushBackground: PushBackground
        var deviceData: DeviceMetadata

        enum CodingKeys: CodingKey {
            case pushToken
            case pushEnablement
            case pushBackground
            case deviceData
        }
    }

    // state related stuff
    var apiKey: String?
    var email: String?
    var anonymousId: String?
    var phoneNumber: String?
    var externalId: String?
    var pushTokenData: PushTokenData?

    // queueing related stuff
    var queue: [KlaviyoRequest]
    var requestsInFlight: [KlaviyoRequest] = []
    var initalizationState = InitializationState.uninitialized
    var flushing = false
    var flushInterval = StateManagementConstants.wifiFlushInterval
    var retryInfo = RetryInfo.retry(StateManagementConstants.initialAttempt)
    var pendingRequests: [PendingRequest] = []
    var pendingProfile: [Profile.ProfileKey: AnyEncodable]?

    enum CodingKeys: String, CodingKey {
        case apiKey
        case email
        case anonymousId
        case phoneNumber
        case externalId
        case queue
        case pushTokenData
    }

    mutating func enqueueRequest(request: KlaviyoRequest) {
        guard queue.count + 1 < StateManagementConstants.maxQueueSize else {
            return
        }
        queue.append(request)
    }

    mutating func updateEmail(email: String, appContextInfo: AppContextInfo) {
        if email.isNotEmptyOrSame(as: self.email, identifier: "email") {
            self.email = email
            enqueueProfileOrTokenRequest(appConextInfo: appContextInfo)
        }
    }

    mutating func updateExternalId(externalId: String, appContextInfo: AppContextInfo) {
        if externalId.isNotEmptyOrSame(as: self.externalId, identifier: "external Id") {
            self.externalId = externalId
            enqueueProfileOrTokenRequest(appConextInfo: appContextInfo)
        }
    }

    mutating func updatePhoneNumber(phoneNumber: String, appContextInfo: AppContextInfo) {
        if phoneNumber.isNotEmptyOrSame(as: self.phoneNumber, identifier: "phone number") {
            self.phoneNumber = phoneNumber
            enqueueProfileOrTokenRequest(appConextInfo: appContextInfo)
        }
    }

    mutating func enqueueProfileOrTokenRequest(appConextInfo: AppContextInfo) {
        guard let apiKey = apiKey,
              let anonymousId = anonymousId else {
            // ND: revist - just log here...
            // environment.emitDeveloperWarning("SDK internal error")
            return
        }
        // if we have push data and we are switching emails
        // we want to associate the token with the new email.
        if let pushTokenData = pushTokenData {
            self.pushTokenData = nil
            let request = buildTokenRequest(
                apiKey: apiKey,
                anonymousId: anonymousId,
                pushToken: pushTokenData.pushToken,
                enablement: pushTokenData.pushEnablement, background: pushTokenData.pushBackground, appContextInfo: appConextInfo)
            enqueueRequest(request: request)
        } else {
            enqueueProfileRequest(
                apiKey: apiKey,
                anonymousId: anonymousId)
        }
    }

    mutating func enqueueProfileRequest(apiKey: String, anonymousId: String) {
        let request = buildProfileRequest(apiKey: apiKey, anonymousId: anonymousId)
        switch request.endpoint {
        case let .createProfile(payload):
            let updatedPayload = updateRequestAndStateWithPendingProfile(profile: payload)
            let request = KlaviyoRequest(apiKey: apiKey, endpoint: .createProfile(updatedPayload), uuid: environment.uuid().uuidString)
            enqueueRequest(request: request)
        default:
            environment.raiseFatalError("Unexpected request type. \(request.endpoint)")
        }
    }

    mutating func updateStateWithProfile(profile: Profile) {
        if let profileEmail = profile.email,
           profileEmail.isNotEmptyOrSame(as: self.email, identifier: "email") {
            email = profileEmail
        }

        if let profilePhoneNumber = profile.phoneNumber,
           profilePhoneNumber.isNotEmptyOrSame(as: self.phoneNumber, identifier: "phone number") {
            phoneNumber = profilePhoneNumber
        }

        if let profileExternalId = profile.externalId,
           profileExternalId.isNotEmptyOrSame(as: self.externalId, identifier: "external id") {
            externalId = profileExternalId
        }
    }

    mutating func updateRequestAndStateWithPendingProfile(profile: CreateProfilePayload) -> CreateProfilePayload {
        guard let pendingProfile = pendingProfile else {
            return profile
        }
        var attributes = profile.data.attributes
        var location = profile.data.attributes.location ?? .init()
        let properties = profile.data.attributes.properties.value as? [String: Any] ?? [:]
        let updatedProfile = Profile.updateProfileWithProperties(dict: pendingProfile)

        if let firstName = updatedProfile.firstName {
            attributes.firstName = attributes.firstName ?? firstName
        }
        if let lastName = updatedProfile.lastName {
            attributes.lastName = attributes.lastName ?? lastName
        }
        if let title = updatedProfile.title {
            attributes.title = attributes.title ?? title
        }
        if let organization = updatedProfile.organization {
            attributes.organization = attributes.organization ?? organization
        }
        if !updatedProfile.properties.isEmpty {
            attributes.properties = AnyCodable(properties.merging(updatedProfile.properties, uniquingKeysWith: { _, new in new }))
        }

        if let address1 = updatedProfile.location?.address1 {
            location.address1 = location.address1 ?? address1
        }
        if let address2 = updatedProfile.location?.address2 {
            location.address2 = location.address2 ?? address2
        }
        if let city = updatedProfile.location?.city {
            location.city = location.city ?? city
        }
        if let region = updatedProfile.location?.region {
            location.region = location.region ?? region
        }
        if let country = updatedProfile.location?.country {
            location.country = location.country ?? country
        }
        if let zip = updatedProfile.location?.zip {
            location.zip = location.zip ?? zip
        }
        if let image = updatedProfile.image {
            attributes.image = attributes.image ?? image
        }
        if let latitude = updatedProfile.location?.latitude {
            location.latitude = location.latitude ?? latitude
        }
        if let longitude = updatedProfile.location?.longitude {
            location.longitude = location.longitude ?? longitude
        }

        attributes.location = location
        self.pendingProfile = nil

        return .init(data: .init(attributes: attributes))
    }

    var isIdentified: Bool {
        email != nil || externalId != nil || phoneNumber != nil
    }

    mutating func reset(preserveTokenData: Bool = true, appContextInfo: AppContextInfo) {
        if isIdentified {
            // If we are still anonymous we want to preserve our anonymous id so we can merge this profile with the new profile.
            anonymousId = environment.uuid().uuidString
        }
        let previousPushTokenData = pushTokenData
        pendingProfile = nil
        email = nil
        externalId = nil
        phoneNumber = nil
        pushTokenData = nil
        if preserveTokenData {
            pushTokenData = previousPushTokenData
            if let apiKey = apiKey,
               let anonymousId = anonymousId,
               let tokenData = previousPushTokenData {
                let payload = PushTokenPayload(
                    pushToken: tokenData.pushToken,
                    enablement: tokenData.pushEnablement.rawValue,
                    background: tokenData.pushBackground.rawValue,
                    profile: Profile().toAPIModel(anonymousId: anonymousId), appContextInfo: appContextInfo)

                let request = KlaviyoRequest(
                    apiKey: apiKey,
                    endpoint: KlaviyoEndpoint.registerPushToken(payload), uuid: environment.uuid().uuidString)

                enqueueRequest(request: request)
            }
        }
    }

    func shouldSendTokenUpdate(newToken: String, enablement: PushEnablement, appContextInfo: AppContextInfo, pushBackground: PushBackground) -> Bool {
        guard let pushTokenData = pushTokenData else {
            return true
        }
        let currentDeviceMetadata = DeviceMetadata(
            context: appContextInfo)
        let newPushTokenData = PushTokenData(
            pushToken: newToken,
            pushEnablement: enablement,
            pushBackground: pushBackground,
            deviceData: currentDeviceMetadata)

        return pushTokenData != newPushTokenData
    }

    func buildProfileRequest(apiKey: String, anonymousId: String, properties: [String: Any] = [:]) -> KlaviyoRequest {
        let payload = ProfilePayload(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            properties: properties,
            anonymousId: anonymousId)

        let endpoint = KlaviyoEndpoint.createProfile(CreateProfilePayload(data: payload))

        return KlaviyoRequest(apiKey: apiKey, endpoint: endpoint, uuid: environment.uuid().uuidString)
    }

    mutating func buildTokenRequest(apiKey: String, anonymousId: String, pushToken: String, enablement: PushEnablement, background: PushBackground, appContextInfo: AppContextInfo) -> KlaviyoRequest {
        var profile: Profile

        if let pendingProfile = pendingProfile {
            profile = Profile.updateProfileWithProperties(
                email: email,
                phoneNumber: phoneNumber,
                externalId: externalId,
                dict: pendingProfile)
            self.pendingProfile = nil
        } else {
            profile = Profile(email: email, phoneNumber: phoneNumber, externalId: externalId)
        }

        let payload = PushTokenPayload(
            pushToken: pushToken,
            enablement: enablement.rawValue,
            background: background.rawValue,
            profile: profile.toAPIModel(anonymousId: anonymousId),
            appContextInfo: appContextInfo)
        let endpoint = KlaviyoEndpoint.registerPushToken(payload)
        return KlaviyoRequest(apiKey: apiKey, endpoint: endpoint, uuid: environment.uuid().uuidString)
    }

    func buildUnregisterRequest(apiKey: String, anonymousId: String, pushToken: String) -> KlaviyoRequest {
        let payload = UnregisterPushTokenPayload(
            pushToken: pushToken,
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            anonymousId: anonymousId)
        let endpoint = KlaviyoEndpoint.unregisterPushToken(payload)
        return KlaviyoRequest(apiKey: apiKey, endpoint: endpoint, uuid: environment.uuid().uuidString)
    }
}

// MARK: Klaviyo state persistence

func saveKlaviyoState(state: KlaviyoState) {
    guard let apiKey = state.apiKey else {
        environment.logger.error("Attempt to save state without an api key.")
        return
    }
    let file = klaviyoStateFile(apiKey: apiKey)
    storeKlaviyoState(fileClient: environment.fileClient, state: state, file: file)
}

private func klaviyoStateFile(apiKey: String) -> URL {
    let fileName = "klaviyo-\(apiKey)-state.json"
    let directory = environment.fileClient.libraryDirectory()
    return directory.appendingPathComponent(fileName, isDirectory: false)
}

private func storeKlaviyoState(fileClient: FileClient, state: KlaviyoState, file: URL) {
    do {
        try fileClient.write(environment.encodeJSON(AnyEncodable(state)), file)
    } catch {
        // ND: handle logger here..
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

private func logDevWarning(for identifier: String) async {
    await environment.emitDeveloperWarning("""
    \(identifier) is either empty or same as what is already set earlier.
    The SDK will ignore this change, please use resetProfile for
    resetting profile identifiers
    """)
}

/// Loads SDK state from disk
/// - Parameter apiKey: the API key that uniquely identiifies the company
/// - Returns: an instance of the `KlaviyoState`
func loadKlaviyoStateFromDisk(apiKey: String) -> KlaviyoState {
    let fileName = klaviyoStateFile(apiKey: apiKey)
    guard environment.fileClient.fileExists(fileName.path) else {
        return createAndStoreInitialState(with: apiKey, at: fileName)
    }
    guard let stateData = try? environment.dataFromUrl(fileName) else {
        environment.logger.error("Klaviyo state file invalid starting from scratch.")
        removeStateFile(at: fileName)
        return createAndStoreInitialState(with: apiKey, at: fileName)
    }
    guard var state: KlaviyoState = try? environment.decoder.decode(stateData) else {
        environment.logger.error("Unable to decode existing state file. Removing.")
        removeStateFile(at: fileName)
        return createAndStoreInitialState(with: apiKey, at: fileName)
    }
    if state.apiKey != apiKey {
        // Clear existing state since we are using a new api state.
        state = KlaviyoState(
            apiKey: apiKey,
            anonymousId: environment.uuid().uuidString,
            queue: [])
    }
    return state
}

private func createAndStoreInitialState(with apiKey: String, at file: URL) -> KlaviyoState {
    let anonymousId = environment.uuid().uuidString
    let state = KlaviyoState(apiKey: apiKey, anonymousId: anonymousId, queue: [], requestsInFlight: [])
    storeKlaviyoState(fileClient: environment.fileClient, state: state, file: file)
    return state
}

extension Profile {
    fileprivate static func updateProfileWithProperties(
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        dict: [Profile.ProfileKey: AnyEncodable]) -> Self {
        var firstName: String?
        var lastName: String?
        var address1: String?
        var address2: String?
        var title: String?
        var organization: String?
        var city: String?
        var region: String?
        var country: String?
        var zip: String?
        var image: String?
        var latitude: Double?
        var longitude: Double?
        var customProperties: [String: Any] = [:]

        for (key, value) in dict {
            switch key {
            case .firstName:
                firstName = value.value as? String
            case .lastName:
                lastName = value.value as? String
            case .address1:
                address1 = value.value as? String
            case .address2:
                address2 = value.value as? String
            case .title:
                title = value.value as? String
            case .organization:
                organization = value.value as? String
            case .city:
                city = value.value as? String
            case .region:
                region = value.value as? String
            case .country:
                country = value.value as? String
            case .zip:
                zip = value.value as? String
            case .image:
                image = value.value as? String
            case .latitude:
                latitude = value.value as? Double
            case .longitude:
                longitude = value.value as? Double
            case let .custom(customKey: customKey):
                customProperties[customKey] = value.value
            }
        }

        let location = Profile.Location(
            address1: address1,
            address2: address2,
            city: city,
            country: country,
            latitude: latitude,
            longitude: longitude,
            region: region,
            zip: zip)

        let profile = Profile(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            firstName: firstName,
            lastName: lastName,
            organization: organization,
            title: title,
            image: image,
            location: location,
            properties: customProperties)

        return profile
    }
}

extension String {
    fileprivate func isNotEmptyOrSame(as state: String?, identifier: String) -> Bool {
        let incoming = trimmingCharacters(in: .whitespacesAndNewlines)
        if incoming.isEmpty || incoming == state {
            // fix - logging
            // await logDevWarning(for: identifier)
        }

        return !incoming.isEmpty && incoming != state
    }
}
