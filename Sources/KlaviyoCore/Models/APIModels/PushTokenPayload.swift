//
//  PushTokenPayload.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import Foundation

public struct PushTokenPayload: Equatable, Codable {
    public let data: PushToken

    public struct PushToken: Equatable, Codable {
        var type = "push-token"
        public var attributes: Attributes

        public init(pushToken: String,
                    enablement: String,
                    background: String,
                    profile: ProfilePayload) {
            attributes = Attributes(
                pushToken: pushToken,
                enablement: enablement,
                background: background,
                profile: profile)
        }

        public struct Attributes: Equatable, Codable {
            public let profile: Profile
            public let token: String
            public let enablementStatus: String
            public let backgroundStatus: String
            public let deviceMetadata: MetaData
            public let platform: String = "ios"
            public let vendor: String = "APNs"

            enum CodingKeys: String, CodingKey {
                case token
                case platform
                case enablementStatus = "enablement_status"
                case profile
                case vendor
                case backgroundStatus = "background"
                case deviceMetadata = "device_metadata"
            }

            public init(pushToken: String,
                        enablement: String,
                        background: String,
                        profile: ProfilePayload) {
                token = pushToken

                enablementStatus = enablement
                backgroundStatus = background
                self.profile = Profile(data: profile)
                deviceMetadata = MetaData(context: environment.appContextInfo())
            }

            public struct Profile: Equatable, Codable {
                public let data: ProfilePayload

                public init(data: ProfilePayload) {
                    self.data = data
                }
            }

            public struct MetaData: Equatable, Codable {
                public let deviceId: String
                public let deviceModel: String
                public let manufacturer: String
                public let osName: String
                public let osVersion: String
                public let appId: String
                public let appName: String
                public let appVersion: String
                public let appBuild: String
                public let environment: String
                public let klaviyoSdk: String
                public let sdkVersion: String

                enum CodingKeys: String, CodingKey {
                    case deviceId = "device_id"
                    case klaviyoSdk = "klaviyo_sdk"
                    case sdkVersion = "sdk_version"
                    case deviceModel = "device_model"
                    case osName = "os_name"
                    case osVersion = "os_version"
                    case manufacturer
                    case appName = "app_name"
                    case appVersion = "app_version"
                    case appBuild = "app_build"
                    case appId = "app_id"
                    case environment
                }

                public init(context: AppContextInfo) {
                    deviceId = context.deviceId
                    deviceModel = context.deviceModel
                    manufacturer = context.manufacturer
                    osName = context.osName
                    osVersion = context.osVersion
                    appId = context.bundleId
                    appName = context.appName
                    appVersion = context.appVersion
                    appBuild = context.appBuild
                    environment = context.environment
                    klaviyoSdk = KlaviyoCore.environment.sdkName()
                    sdkVersion = KlaviyoCore.environment.sdkVersion()
                }
            }
        }
    }

    public init(data: PushTokenPayload.PushToken) {
        self.data = data
    }

    public init(pushToken: String,
                enablement: String,
                background: String,
                profile: ProfilePayload) {
        data = PushToken(
            pushToken: pushToken,
            enablement: enablement,
            background: background,
            profile: profile)
    }
}
