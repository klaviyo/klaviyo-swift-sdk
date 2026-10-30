//
//  PushTokenData.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

import Foundation

public typealias DeviceMetadata = PushTokenPayload.PushToken.Attributes.MetaData

public struct PushTokenData: Equatable, Codable {
    public var pushToken: String
    public var pushEnablement: PushEnablement
    public var pushBackground: PushBackground
    public var deviceData: DeviceMetadata

    public init(
        pushToken: String,
        pushEnablement: PushEnablement,
        pushBackground: PushBackground,
        deviceData: DeviceMetadata
    ) {
        self.pushToken = pushToken
        self.pushEnablement = pushEnablement
        self.pushBackground = pushBackground
        self.deviceData = deviceData
    }
}

extension PushTokenData {
    /// Reconstructs a `PushTokenData` from a registered-push-token request payload, so a successful
    /// registration can be written back to `IdentityStore`. Non-failable: `token`/`deviceMetadata`
    /// are non-optional and the enablement/background conversions fall back
    /// (`?? .authorized` / `?? .available`), so there is no failure path.
    init(_ payload: PushTokenPayload) {
        let attributes = payload.data.attributes
        self.init(
            pushToken: attributes.token,
            pushEnablement: PushEnablement(rawValue: attributes.enablementStatus) ?? .authorized,
            pushBackground: PushBackground(rawValue: attributes.backgroundStatus) ?? .available,
            deviceData: attributes.deviceMetadata
        )
    }
}
