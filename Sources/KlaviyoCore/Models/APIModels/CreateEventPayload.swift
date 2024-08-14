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

                public init(data: ProfilePayload) {
                    self.data = data
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
                self.time = time ?? environment.date()
                self.uniqueId = uniqueId ?? environment.uuid().uuidString
                profile = Profile(
                    data: ProfilePayload(
                        email: email,
                        phoneNumber: phoneNumber,
                        externalId: externalId,
                        anonymousId: anonymousId ?? "")
                )
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
        public init(name: String,
                    properties: [String: Any]? = nil,
                    email: String? = nil,
                    phoneNumber: String? = nil,
                    externalId: String? = nil,
                    anonymousId: String? = nil,
                    value: Double? = nil,
                    time: Date? = nil,
                    uniqueId: String? = nil,
                    pushToken: String? = nil) {
            attributes = Attributes(
                name: name,
                properties: properties?.appendMetadataToProperties(pushToken: pushToken),
                email: email,
                phoneNumber: phoneNumber,
                externalId: externalId,
                anonymousId: anonymousId,
                value: value,
                time: time,
                uniqueId: uniqueId)
        }
    }

    public var data: Event
    public init(data: Event) {
        self.data = data
    }
}

extension Dictionary where Key == String, Value == Any {
    fileprivate func appendMetadataToProperties(pushToken: String?) -> [String: Any]? {
        let context = environment.appContextInfo()
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
            "Push Token": pushToken ?? ""
        ]

        return merging(metadata) { _, new in new }
    }
}
