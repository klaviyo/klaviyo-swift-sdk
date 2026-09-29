//
//  CreateSubscriptionPayload.swift
//
//
//  Created by Aahil Nishad on 7/7/26.
//

import Foundation

public struct CreateSubscriptionPayload: Equatable, Codable {
    public let data: SubscriptionData

    public init(listId: String, profile: ProfilePayload, customSource: String? = nil) {
        data = SubscriptionData(listId: listId, profile: profile, customSource: customSource)
    }

    public struct SubscriptionData: Equatable, Codable {
        public let type = "subscription"
        public let attributes: Attributes
        public let relationships: Relationships

        public init(listId: String, profile: ProfilePayload, customSource: String?) {
            attributes = Attributes(customSource: customSource, profile: .init(data: profile))
            relationships = Relationships(list: .init(data: .init(id: listId)))
        }

        public struct Attributes: Equatable, Codable {
            public let customSource: String?
            public let profile: Profile

            enum CodingKeys: String, CodingKey {
                case customSource = "custom_source"
                case profile
            }

            public struct Profile: Equatable, Codable {
                public let data: ProfilePayload
            }
        }

        public struct Relationships: Equatable, Codable {
            public let list: ListRelationship

            public struct ListRelationship: Equatable, Codable {
                public let data: ListData

                public struct ListData: Equatable, Codable {
                    public let type = "list"
                    public let id: String
                }
            }
        }
    }
}
