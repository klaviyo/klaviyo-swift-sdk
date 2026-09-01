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

typealias PushTokenData = KlaviyoCore.PushTokenData

struct KlaviyoState: Equatable {
    enum InitializationState: Equatable {
        case uninitialized
        case initializing
        case initialized
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
    // The durable pending queue lives in the Core `QueueStore` (resolved per apiKey); `KlaviyoState`
    // only holds the in-memory in-flight lease. See `QueueStore` and `enqueueRequest`.
    var requestsInFlight: [KlaviyoRequest] = []
    var initalizationState = InitializationState.uninitialized
    var flushing = false
    var flushInterval = StateManagementConstants.wifiFlushInterval
    var retryState = RetryState.retry(StateManagementConstants.initialAttempt)
    var pendingProfile: [Profile.ProfileKey: AnyEncodable]?

    init(
        apiKey: String? = nil,
        email: String? = nil,
        anonymousId: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        pushTokenData: PushTokenData? = nil,
        requestsInFlight: [KlaviyoRequest] = [],
        initalizationState: InitializationState = .uninitialized,
        flushing: Bool = false,
        flushInterval: Double = StateManagementConstants.wifiFlushInterval,
        retryState: RetryState = .retry(StateManagementConstants.initialAttempt),
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
        self.requestsInFlight = requestsInFlight
        self.initalizationState = initalizationState
        self.flushing = flushing
        self.flushInterval = flushInterval
        self.retryState = retryState
        self.pendingProfile = pendingProfile
    }

    /// Routes an enqueue to the Core `QueueStore` for the current apiKey. Front-insert for
    /// high-priority requests and capacity/eviction live inside `QueueStore.enqueue` (keyed on
    /// `request.priority`), so this is now a thin forwarder.
    mutating func enqueueRequest(request: KlaviyoRequest) {
        guard let apiKey = apiKey else {
            environment.emitDeveloperWarning("Attempt to enqueue without an api key.")
            return
        }
        QueueStore.store(for: apiKey).enqueue(request)
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

    func requestIdentity(apiKey: String, anonymousId: String) -> RequestIdentity {
        RequestIdentity(
            apiKey: apiKey,
            anonymousId: anonymousId,
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId
        )
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

    var isIdentified: Bool {
        email != nil || externalId != nil || phoneNumber != nil
    }

    mutating func reset(preserveTokenData: Bool = true) {
        if isIdentified {
            // A formerly-identified profile is being cleared: mint a fresh anonymous id via the
            // canonical minter so the resulting anonymous profile is distinct.
            anonymousId = IdentityStore.shared.mintNewAnonymousId()
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
                let profile = ProfilePayload(Profile(), anonymousId: anonymousId)
                let request = RequestFactory.tokenRequest(
                    apiKey: apiKey,
                    pushToken: tokenData.pushToken,
                    enablement: tokenData.pushEnablement,
                    background: tokenData.pushBackground.rawValue,
                    profile: profile
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
}

// MARK: Klaviyo state persistence

/// Not `private` — `LegacyStateMigration` needs this path to locate the legacy state file.
func klaviyoStateFile(apiKey: String) -> URL {
    let fileName = "klaviyo-\(apiKey)-state.json"
    let directory = environment.fileClient.libraryDirectory()
    return directory.appendingPathComponent(fileName, isDirectory: false)
}
