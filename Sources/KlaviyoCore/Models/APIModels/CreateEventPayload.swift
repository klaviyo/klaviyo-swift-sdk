//
//  CreateEventPayload.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import Foundation
import KlaviyoSDKDependencies

public struct CreateEventPayload: Equatable, Codable, Sendable {
    public struct Event: Equatable, Codable, Sendable {
        public struct Attributes: Equatable, Codable, Sendable {
            public struct Metric: Equatable, Codable, Sendable {
                public let data: MetricData

                public struct MetricData: Equatable, Codable, Sendable {
                    var type: String = "metric"

                    public let attributes: MetricAttributes

                    public init(name: String) {
                        attributes = .init(name: name)
                    }

                    public struct MetricAttributes: Equatable, Codable, Sendable {
                        public let name: String
                    }
                }

                public init(name: String) {
                    data = .init(name: name)
                }
            }

            public struct Profile: Equatable, Codable, Sendable {
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
                self.properties = AnyCodable(properties ?? [:])
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
                    pushToken: String? = nil,
                    appContextInfo: AppContextInfo) {
            attributes = Attributes(
                name: name,
                properties: properties?.appendMetadataToProperties(context: appContextInfo, pushToken: pushToken),
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
    func appendMetadataToProperties(context: AppContextInfo, pushToken: String?) -> [String: Any]? {
        var metadata: [String: Any] = [
            "Device ID": context.deviceId,
            "Device Manufacturer": context.manufacturer,
            "Device Model": context.deviceModel,
            "OS Name": context.osName,
            "OS Version": context.osVersion,
            "SDK Name": context.klaviyoSdk,
            "SDK Version": context.sdkVersion,
            "App Name": context.appName,
            "App ID": context.bundleId,
            "App Version": context.appVersion,
            "App Build": context.appBuild
        ]

        if let pushToken {
            metadata["Push Token"] = pushToken
        }

        return merging(metadata) { _, new in new }
    }
}
