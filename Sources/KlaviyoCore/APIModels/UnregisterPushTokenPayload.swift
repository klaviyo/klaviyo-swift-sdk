//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import Foundation

public struct UnregisterPushTokenPayload: Equatable, Codable {
    public let data: PushToken

    public init(pushToken: String,
                profile: PublicProfile,
                anonymousId: String) {
        data = .init(
            pushToken: pushToken,
            profile: profile,
            anonymousId: anonymousId)
    }

    public struct PushToken: Equatable, Codable {
        var type = "push-token-unregister"
        public var attributes: Attributes

        public init(pushToken: String,
                    profile: PublicProfile,
                    anonymousId: String) {
            attributes = .init(
                pushToken: pushToken,
                profile: profile,
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
                        profile: PublicProfile,
                        anonymousId: String) {
                token = pushToken
                self.profile = .init(attributes: profile, anonymousId: anonymousId)
            }

            public struct Profile: Equatable, Codable {
                public let data: CreateProfilePayload.Profile

                public init(attributes: PublicProfile,
                            anonymousId: String) {
                    data = .init(profile: attributes, anonymousId: anonymousId)
                }
            }
        }
    }
}
