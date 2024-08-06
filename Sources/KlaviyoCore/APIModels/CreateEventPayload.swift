//
//  CreateEventPayload.swift
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
                public let data: ProfilePayload

                public init(email: String? = nil,
                            phoneNumber: String? = nil,
                            externalId: String? = nil,
                            firstName: String? = nil,
                            lastName: String? = nil,
                            organization: String? = nil,
                            title: String? = nil,
                            image: String? = nil,
                            location: ProfilePayload.Attributes.Location? = nil,
                            properties: [String: Any]? = nil,
                            anonymousId: String) {
                    data = ProfilePayload(attributes: ProfilePayload.Attributes(
                        email: email,
                        phoneNumber: phoneNumber,
                        externalId: externalId,
                        firstName: firstName,
                        lastName: lastName,
                        organization: organization,
                        title: title,
                        image: image,
                        location: location,
                        properties: properties,
                        anonymousId: anonymousId))
                }
            }

            public let metric: Metric
            public var properties: AnyCodable
            public let profile: Profile
            public let time: Date
            public let value: Double?
            public let uniqueId: String
            public init(name: String,
                        properties: [String: Any]? = nil,
                        email: String? = nil,
                        phoneNumber: String? = nil,
                        externalId: String? = nil,
                        anonymousId: String? = nil,
                        value: Double? = nil,
                        time: Date? = nil,
                        uniqueId: String? = nil) {
                metric = Metric(name: name)
                self.properties = AnyCodable(properties)
                self.value = value
                self.time = time ?? Date()
                self.uniqueId = uniqueId ?? analytics.uuid().uuidString

                profile = Profile(
                    email: email,
                    phoneNumber: phoneNumber,
                    externalId: externalId,
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
        // TODO: fixme
//        public init(event: PublicEvent,
//                    anonymousId: String? = nil) {
//            attributes = Attributes(attributes: event, anonymousId: anonymousId)
//        }
    }

    mutating func appendMetadataToProperties(pushToken: String) {
        let context = KlaviyoAPI._appContextInfo
        // TODO: Fixme
        let metadata: [String: Any] = [
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
            "Push Token": pushToken
        ]

        let originalProperties = data.attributes.properties.value as? [String: Any] ?? [:]
        data.attributes.properties = AnyCodable(originalProperties.merging(metadata) { _, new in new })
    }

    public var data: Event
    public init(data: Event) {
        self.data = data
    }
}
