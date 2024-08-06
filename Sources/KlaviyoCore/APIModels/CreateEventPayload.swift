//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import AnyCodable
import Foundation

public struct CreateEventPayload: Equatable, Codable {
    public struct Event: Equatable, Codable {
        public struct Attributes: Equatable, Codable {
            public struct Metric: Equatable, Codable {
                public let data: MetricData

                public struct MetricData: Equatable, Codable {
                    var type: String = "metric"

                    public let attributes: MetricAttributes

                    public init(name: String) {
                        attributes = .init(name: name)
                    }

                    public struct MetricAttributes: Equatable, Codable {
                        public let name: String
                    }
                }

                public init(name: String) {
                    data = .init(name: name)
                }
            }

            public struct Profile: Equatable, Codable {
                public let data: CreateProfilePayload.Profile

                public init(attributes: PublicProfile,
                            anonymousId: String) {
                    data = .init(profile: attributes, anonymousId: anonymousId)
                }
            }

            public let metric: Metric
            public var properties: AnyCodable
            public let profile: Profile
            public let time: Date
            public let value: Double?
            public let uniqueId: String
            public init(attributes: PublicEvent,
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
        public var attributes: Attributes
        public init(event: PublicEvent,
                    anonymousId: String? = nil) {
            attributes = .init(attributes: event, anonymousId: anonymousId)
        }
    }

    mutating func appendMetadataToProperties() {
        let context = KlaviyoAPI._appContextInfo
        // TODO: Fixme
//                let metadata: [String: Any] = [
//                    "Device ID": context.deviceId,
//                    "Device Manufacturer": context.manufacturer,
//                    "Device Model": context.deviceModel,
//                    "OS Name": context.osName,
//                    "OS Version": context.osVersion,
//                    "SDK Name": __klaviyoSwiftName,
//                    "SDK Version": __klaviyoSwiftVersion,
//                    "App Name": context.appName,
//                    "App ID": context.bundleId,
//                    "App Version": context.appVersion,
//                    "App Build": context.appBuild,
//                    "Push Token": analytics.state().pushTokenData?.pushToken as Any
//                ]

        let metadata = [String: Any]()
        let originalProperties = data.attributes.properties.value as? [String: Any] ?? [:]
        data.attributes.properties = AnyCodable(originalProperties.merging(metadata) { _, new in new })
    }

    public var data: Event
    public init(data: Event) {
        self.data = data
    }
}
