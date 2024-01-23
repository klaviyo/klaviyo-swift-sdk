//
//  InternalAPIModels.swift
//  Internal models typically used at the networking layer.
//  NOTE: Ensure that new request types are equatable and encodable.
//
//  Created by Noah Durell on 11/25/22.
//

import AnyCodable
import Foundation

extension KlaviyoAPI.KlaviyoRequest {
    private static let _appContextInfo = environment.analytics.appContextInfo()

    enum KlaviyoEndpoint: Equatable, Codable {
        struct CreateProfilePayload: Equatable, Codable {
            /**
             Internal structure which has details not needed by the API.
             */
            struct Profile: Equatable, Codable {
                var type = "profile"
                struct Attributes: Equatable, Codable {
                    let email: String?
                    let phoneNumber: String?
                    let externalId: String?
                    let anonymousId: String
                    var firstName: String?
                    var lastName: String?
                    var organization: String?
                    var title: String?
                    var image: String?
                    var location: KlaviyoSwift.Profile.Location?
                    var properties: AnyCodable
                    enum CodingKeys: String, CodingKey {
                        case email
                        case phoneNumber = "phone_number"
                        case externalId = "external_id"
                        case anonymousId = "anonymous_id"
                        case firstName = "first_name"
                        case lastName = "last_name"
                        case organization
                        case title
                        case image
                        case location
                        case properties
                    }

                    init(attributes: KlaviyoSwift.Profile,
                         anonymousId: String) {
                        email = attributes.email
                        phoneNumber = attributes.phoneNumber
                        externalId = attributes.externalId
                        firstName = attributes.firstName
                        lastName = attributes.lastName
                        organization = attributes.organization
                        title = attributes.title
                        image = attributes.image
                        location = attributes.location
                        properties = AnyCodable(attributes.properties)
                        self.anonymousId = anonymousId
                    }
                }

                var attributes: Attributes
                init(profile: KlaviyoSwift.Profile, anonymousId: String) {
                    attributes = Attributes(
                        attributes: profile,
                        anonymousId: anonymousId)
                }

                init(attributes: Attributes) {
                    self.attributes = attributes
                }
            }

            var data: Profile
        }

        struct CreateEventPayload: Equatable, Codable {
            struct Event: Equatable, Codable {
                struct Attributes: Equatable, Codable {
                    struct Metric: Equatable, Codable {
                        let data: MetricData

                        struct MetricData: Equatable, Codable {
                            var type: String = "metric"

                            let attributes: MetricAttributes

                            init(name: String) {
                                attributes = .init(name: name)
                            }

                            struct MetricAttributes: Equatable, Codable {
                                let name: String
                            }
                        }

                        init(name: String) {
                            data = .init(name: name)
                        }
                    }

                    struct Profile: Equatable, Codable {
                        let data: CreateProfilePayload.Profile

                        init(attributes: KlaviyoSwift.Profile,
                             anonymousId: String) {
                            data = .init(profile: attributes, anonymousId: anonymousId)
                        }
                    }

                    let metric: Metric
                    var properties: AnyCodable
                    let profile: Profile
                    let time: Date
                    let value: Double?
                    let uniqueId: String
                    init(attributes: KlaviyoSwift.Event,
                         anonymousId: String? = nil) {
                        metric = Metric(name: attributes.metric.name.value)
                        properties = AnyCodable(attributes.properties)
                        value = attributes.value
                        time = attributes.time
                        uniqueId = attributes.uniqueId

                        profile = .init(attributes: .init(
                            email: attributes.identifiers?.email,
                            phoneNumber: attributes.identifiers?.phoneNumber,
                            externalId: attributes.identifiers?.externalId),
                        anonymousId: anonymousId ?? "")
                    }

                    enum CodingKeys: String, CodingKey {
                        case metric
                        case properties
                        case profile
                        case time
                        case value
                        case uniqueId = "unique_id"
                    }
                }

                var type = "event"
                var attributes: Attributes
                init(event: KlaviyoSwift.Event,
                     anonymousId: String? = nil) {
                    attributes = .init(attributes: event, anonymousId: anonymousId)
                }
            }

            mutating func appendMetadataToProperties() {
                let context = KlaviyoAPI.KlaviyoRequest._appContextInfo
                let metadata = [
                    "Device ID": context.deviceId,
                    "Device Manufacturer": context.manufacturer,
                    "Device Model": context.deviceModel,
                    "OS Name": context.osName,
                    "OS Version": context.osVersion,
                    "SDK Name": __klaviyoSwiftName,
                    "SDK Version": __klaviyoSwiftVersion,
                    "App Name": context.appName,
                    "App ID": context.bundleId,
                    "App Version": context.appVersion,
                    "App Build": context.appBuild,
                    "Push Token": environment.analytics.state().pushTokenData?.pushToken as Any
                ]
                let originalProperties = data.attributes.properties.value as? [String: Any] ?? [:]
                data.attributes.properties = AnyCodable(originalProperties.merging(metadata) { _, new in new })
            }

            var data: Event
            init(data: Event) {
                self.data = data
            }
        }

        struct PushTokenPayload: Equatable, Codable {
            let data: PushToken

            init(pushToken: String,
                 enablement: String,
                 background: String,
                 profile: KlaviyoSwift.Profile,
                 anonymousId: String) {
                data = .init(
                    pushToken: pushToken,
                    enablement: enablement,
                    background: background,
                    profile: profile,
                    anonymousId: anonymousId)
            }

            struct PushToken: Equatable, Codable {
                var type = "push-token"
                var attributes: Attributes

                init(pushToken: String,
                     enablement: String,
                     background: String,
                     profile: KlaviyoSwift.Profile,
                     anonymousId: String) {
                    attributes = .init(
                        pushToken: pushToken,
                        enablement: enablement,
                        background: background,
                        profile: profile,
                        anonymousId: anonymousId)
                }

                struct Attributes: Equatable, Codable {
                    let profile: Profile
                    let token: String
                    let enablementStatus: String
                    let backgroundStatus: String
                    let deviceMetadata: MetaData
                    let platform: String = "ios"
                    let vendor: String = "APNs"

                    enum CodingKeys: String, CodingKey {
                        case token
                        case platform
                        case enablementStatus = "enablement_status"
                        case profile
                        case vendor
                        case backgroundStatus = "background"
                        case deviceMetadata = "device_metadata"
                    }

                    init(pushToken: String,
                         enablement: String,
                         background: String,
                         profile: KlaviyoSwift.Profile,
                         anonymousId: String) {
                        token = pushToken

                        enablementStatus = enablement
                        backgroundStatus = background
                        self.profile = .init(attributes: profile, anonymousId: anonymousId)
                        deviceMetadata = .init(context: KlaviyoAPI.KlaviyoRequest._appContextInfo)
                    }

                    struct Profile: Equatable, Codable {
                        let data: CreateProfilePayload.Profile

                        init(attributes: KlaviyoSwift.Profile,
                             anonymousId: String) {
                            data = .init(profile: attributes, anonymousId: anonymousId)
                        }
                    }

                    struct MetaData: Equatable, Codable {
                        let deviceId: String
                        let deviceModel: String
                        let manufacturer: String
                        let osName: String
                        let osVersion: String
                        let appId: String
                        let appName: String
                        let appVersion: String
                        let appBuild: String
                        let environment: String
                        let klaviyoSdk: String
                        let sdkVersion: String

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

                        init(context: AppContextInfo) {
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
                            klaviyoSdk = __klaviyoSwiftName
                            sdkVersion = __klaviyoSwiftVersion
                        }
                    }
                }
            }
        }

        struct UnregisterPushTokenPayload: Equatable, Codable {
            let data: PushToken

            init(pushToken: String,
                 profile: KlaviyoSwift.Profile,
                 anonymousId: String) {
                data = .init(
                    pushToken: pushToken,
                    profile: profile,
                    anonymousId: anonymousId)
            }

            struct PushToken: Equatable, Codable {
                var type = "push-token-unregister"
                var attributes: Attributes

                init(pushToken: String,
                     profile: KlaviyoSwift.Profile,
                     anonymousId: String) {
                    attributes = .init(
                        pushToken: pushToken,
                        profile: profile,
                        anonymousId: anonymousId)
                }

                struct Attributes: Equatable, Codable {
                    let profile: Profile
                    let token: String
                    let platform: String = "ios"
                    let vendor: String = "APNs"

                    enum CodingKeys: String, CodingKey {
                        case token
                        case platform
                        case profile
                        case vendor
                    }

                    init(pushToken: String,
                         profile: KlaviyoSwift.Profile,
                         anonymousId: String) {
                        token = pushToken
                        self.profile = .init(attributes: profile, anonymousId: anonymousId)
                    }

                    struct Profile: Equatable, Codable {
                        let data: CreateProfilePayload.Profile

                        init(attributes: KlaviyoSwift.Profile,
                             anonymousId: String) {
                            data = .init(profile: attributes, anonymousId: anonymousId)
                        }
                    }
                }
            }
        }

        case createProfile(CreateProfilePayload)
        case createEvent(CreateEventPayload)
        case registerPushToken(PushTokenPayload)
        case unregisterPushToken(UnregisterPushTokenPayload)
    }
}

extension Profile.Location: Codable {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        address1 = try values.decode(String.self, forKey: .address1)
        address2 = try values.decode(String.self, forKey: .address2)
        city = try values.decode(String.self, forKey: .city)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        region = try values.decode(String.self, forKey: .region)
        self.zip = try values.decode(String.self, forKey: .zip)
        timezone = try values.decode(String.self, forKey: .timezone)
        country = try values.decode(String.self, forKey: .country)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address1, forKey: .address1)
        try container.encode(address2, forKey: .address2)
        try container.encode(city, forKey: .city)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(region, forKey: .region)
        try container.encode(zip, forKey: .zip)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(country, forKey: .country)
    }

    enum CodingKeys: CodingKey {
        case address1
        case address2
        case city
        case country
        case latitude
        case longitude
        case region
        case zip
        case timezone
    }
}
