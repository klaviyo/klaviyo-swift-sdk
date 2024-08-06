//
//  UnregisterPushTokenPayload.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import Foundation

public struct UnregisterPushTokenPayload: Equatable, Codable {
    public let data: PushToken

    public init(pushToken: String,
                email: String? = nil,
                phoneNumber: String? = nil,
                externalId: String? = nil,
                anonymousId: String) {
        data = PushToken(
            pushToken: pushToken,
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            anonymousId: anonymousId)
    }

    public struct PushToken: Equatable, Codable {
        var type = "push-token-unregister"
        public let attributes: Attributes

        public init(pushToken: String,
                    email: String? = nil,
                    phoneNumber: String? = nil,
                    externalId: String? = nil,
                    anonymousId: String) {
            attributes = Attributes(
                pushToken: pushToken,
                email: email,
                phoneNumber: phoneNumber,
                externalId: externalId,
                anonymousId: anonymousId)
        }

        public struct Attributes: Equatable, Codable {
            public let profile: Profile
            public let token: String
            public let platform: String = "ios"
            public let vendor: String = "APNs"

            enum CodingKeys: String, CodingKey {
                case token
                case platform
                case profile
                case vendor
            }

            public init(pushToken: String,
                        email: String? = nil,
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
                token = pushToken
                profile = Profile(
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
                    anonymousId: anonymousId)
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
        }
    }
}
