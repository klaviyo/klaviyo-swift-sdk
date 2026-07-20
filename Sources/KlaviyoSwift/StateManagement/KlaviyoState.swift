//
//  KlaviyoState.swift
//
//
//  Created by Noah Durell on 12/1/22.
//

import AnyCodable
import Foundation
import KlaviyoCore
import UIKit

typealias DeviceMetadata = PushTokenPayload.PushToken.Attributes.MetaData

struct KlaviyoState: Equatable, Codable {
    enum InitializationState: Equatable, Codable {
        case uninitialized
        case initializing
        case initialized
    }

    enum PendingRequest: Equatable {
        case event(Event)
        case aggregateEvent(Data)
        case profile(Profile)
        case pushToken(String, PushEnablement)
        case setEmail(String)
        case setExternalId(String)
        case setPhoneNumber(String)
    }

    struct PushTokenData: Equatable, Codable {
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
    var identity: ProfileData

    // Computed shims forwarding to `identity.*` so the rest of KlaviyoSwift compiles unchanged.
    var email: String? {
        get { identity.email }
        set { identity.email = newValue }
    }

    var phoneNumber: String? {
        get { identity.phoneNumber }
        set { identity.phoneNumber = newValue }
    }

    var externalId: String? {
        get { identity.externalId }
        set { identity.externalId = newValue }
    }

    var anonymousId: String? {
        get { identity.anonymousId }
        set { identity.anonymousId = newValue }
    }

    var pushTokenData: PushTokenData?

    // queueing related stuff
    var queue: [KlaviyoRequest]
    var requestsInFlight: [KlaviyoRequest] = []
    var initalizationState = InitializationState.uninitialized
    var flushing = false
    var flushInterval = StateManagementConstants.wifiFlushInterval
    var retryState = RetryState.retry(StateManagementConstants.initialAttempt)
    var pendingRequests: [PendingRequest] = []
    var pendingProfile: [Profile.ProfileKey: AnyEncodable]?

    enum CodingKeys: CodingKey {
        case apiKey
        case identity
        case queue
        case pushTokenData
    }

    /// Legacy coding keys for migrating state files written before identity was composed into `ProfileData`.
    private enum LegacyCodingKeys: CodingKey {
        case email, anonymousId, phoneNumber, externalId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        pushTokenData = try container.decodeIfPresent(PushTokenData.self, forKey: .pushTokenData)
        queue = try container.decodeIfPresent([KlaviyoRequest].self, forKey: .queue) ?? []

        if let identity = try container.decodeIfPresent(ProfileData.self, forKey: .identity) {
            // New format: identity is a nested object.
            self.identity = identity
        } else {
            // Legacy format: identity fields were stored at the top level.
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            identity = try ProfileData(
                email: legacy.decodeIfPresent(String.self, forKey: .email),
                phoneNumber: legacy.decodeIfPresent(String.self, forKey: .phoneNumber),
                externalId: legacy.decodeIfPresent(String.self, forKey: .externalId),
                anonymousId: legacy.decodeIfPresent(String.self, forKey: .anonymousId)
            )
        }
    }

    init(
        apiKey: String? = nil,
        email: String? = nil,
        anonymousId: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        pushTokenData: PushTokenData? = nil,
        queue: [KlaviyoRequest],
        requestsInFlight: [KlaviyoRequest] = [],
        initalizationState: InitializationState = .uninitialized,
        flushing: Bool = false,
        flushInterval: Double = StateManagementConstants.wifiFlushInterval,
        retryState: RetryState = .retry(StateManagementConstants.initialAttempt),
        pendingRequests: [PendingRequest] = [],
        pendingProfile: [Profile.ProfileKey: AnyEncodable]? = nil
    ) {
        self.apiKey = apiKey
        identity = ProfileData(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            anonymousId: anonymousId
        )
        self.pushTokenData = pushTokenData
        self.queue = queue
        self.requestsInFlight = requestsInFlight
        self.initalizationState = initalizationState
        self.flushing = flushing
        self.flushInterval = flushInterval
        self.retryState = retryState
        self.pendingRequests = pendingRequests
        self.pendingProfile = pendingProfile
    }

    mutating func enqueueRequest(request: KlaviyoRequest) {
        guard queue.count + 1 < StateManagementConstants.maxQueueSize else {
            return
        }
        queue.append(request)
    }

    mutating func updateEmail(email: String) {
        if email.isNotEmptyOrSame(as: self.email, identifier: "email") {
            self.email = email.trimWhiteSpaceOrReturnNilIfEmpty()
            enqueueProfileOrTokenRequest()
        }
    }

    mutating func updateExternalId(externalId: String) {
        if externalId.isNotEmptyOrSame(as: self.externalId, identifier: "external Id") {
            self.externalId = externalId.trimWhiteSpaceOrReturnNilIfEmpty()
            enqueueProfileOrTokenRequest()
        }
    }

    mutating func updatePhoneNumber(phoneNumber: String) {
        if phoneNumber.isNotEmptyOrSame(as: self.phoneNumber, identifier: "phone number") {
            self.phoneNumber = phoneNumber.trimWhiteSpaceOrReturnNilIfEmpty()
            enqueueProfileOrTokenRequest()
        }
    }

    mutating func enqueueProfileOrTokenRequest() {
        guard let apiKey = apiKey,
              let anonymousId = anonymousId else {
            environment.emitDeveloperWarning("SDK internal error")
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
                enablement: pushTokenData.pushEnablement
            )
            enqueueRequest(request: request)
        } else {
            enqueueProfileRequest(
                apiKey: apiKey,
                anonymousId: anonymousId
            )
        }
    }

    mutating func enqueueProfileRequest(apiKey: String, anonymousId: String) {
        let request = buildProfileRequest(apiKey: apiKey, anonymousId: anonymousId)
        switch request.endpoint {
        case let .createProfile(_, payload):
            let updatedPayload = updateRequestAndStateWithPendingProfile(profile: payload)
            let request = KlaviyoRequest(endpoint: .createProfile(apiKey, updatedPayload))
            enqueueRequest(request: request)
        default:
            environment.raiseFatalError("Unexpected request type. \(request.endpoint)")
        }
    }

    mutating func updateStateWithProfile(profile: Profile) {
        if let profileEmail = profile.email,
           profileEmail.isNotEmptyOrSame(as: self.email, identifier: "email") {
            email = profileEmail.trimWhiteSpaceOrReturnNilIfEmpty()
        }

        if let profilePhoneNumber = profile.phoneNumber,
           profilePhoneNumber.isNotEmptyOrSame(as: self.phoneNumber, identifier: "phone number") {
            phoneNumber = profilePhoneNumber.trimWhiteSpaceOrReturnNilIfEmpty()
        }

        if let profileExternalId = profile.externalId,
           profileExternalId.isNotEmptyOrSame(as: self.externalId, identifier: "external id") {
            externalId = profileExternalId.trimWhiteSpaceOrReturnNilIfEmpty()
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

    mutating func reset(preserveTokenData: Bool = true) {
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
                    profile: Profile().toAPIModel(anonymousId: anonymousId)
                )

                let request = KlaviyoRequest(
                    endpoint: KlaviyoEndpoint.registerPushToken(apiKey, payload)
                )

                enqueueRequest(request: request)
            }
        }
    }

    func shouldSendTokenUpdate(newToken: String, enablement: PushEnablement) -> Bool {
        guard let pushTokenData = pushTokenData else {
            return true
        }
        let currentDeviceMetadata = DeviceMetadata(context: environment.appContextInfo())
        let newPushTokenData = PushTokenData(
            pushToken: newToken,
            pushEnablement: enablement,
            pushBackground: environment.getBackgroundSetting(),
            deviceData: currentDeviceMetadata
        )

        return pushTokenData != newPushTokenData
    }

    func buildProfileRequest(apiKey: String, anonymousId: String, properties: [String: Any] = [:]) -> KlaviyoRequest {
        let payload = ProfilePayload(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            properties: properties,
            anonymousId: anonymousId
        )

        let endpoint = KlaviyoEndpoint.createProfile(apiKey, CreateProfilePayload(data: payload))

        return KlaviyoRequest(endpoint: endpoint)
    }

    mutating func buildTokenRequest(apiKey: String, anonymousId: String, pushToken: String, enablement: PushEnablement) -> KlaviyoRequest {
        var profile: Profile

        if let pendingProfile = pendingProfile {
            profile = Profile.updateProfileWithProperties(
                email: email,
                phoneNumber: phoneNumber,
                externalId: externalId,
                dict: pendingProfile
            )
            self.pendingProfile = nil
        } else {
            profile = Profile(email: email, phoneNumber: phoneNumber, externalId: externalId)
        }

        let payload = PushTokenPayload(
            pushToken: pushToken,
            enablement: enablement.rawValue,
            background: environment.getBackgroundSetting().rawValue,
            profile: profile.toAPIModel(anonymousId: anonymousId)
        )
        let endpoint = KlaviyoEndpoint.registerPushToken(apiKey, payload)
        return KlaviyoRequest(endpoint: endpoint)
    }

    func buildUnregisterRequest(apiKey: String, anonymousId: String, pushToken: String) -> KlaviyoRequest {
        let payload = UnregisterPushTokenPayload(
            pushToken: pushToken,
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            anonymousId: anonymousId
        )
        let endpoint = KlaviyoEndpoint.unregisterPushToken(apiKey, payload)
        return KlaviyoRequest(endpoint: endpoint)
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
        try environment.fileClient.write(environment.encodeJSON(AnyEncodable(state)), file)
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
            queue: []
        )
    }
    return state
}

private func createAndStoreInitialState(with apiKey: String, at file: URL) -> KlaviyoState {
    let anonymousId = environment.uuid().uuidString
    let state = KlaviyoState(apiKey: apiKey, anonymousId: anonymousId, queue: [], requestsInFlight: [])
    storeKlaviyoState(state: state, file: file)
    return state
}
