//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import AnyCodable
import Foundation

public struct CreateProfilePayload: Equatable, Codable {
    public init(data: CreateProfilePayload.Profile) {
        self.data = data
    }

    /**
     Internal structure which has details not needed by the API.
     */
    public struct Profile: Equatable, Codable {
        var type = "profile"
        public struct Attributes: Equatable, Codable {
            public let email: String?
            public let phoneNumber: String?
            public let externalId: String?
            public let anonymousId: String
            public var firstName: String?
            public var lastName: String?
            public var organization: String?
            public var title: String?
            public var image: String?
            public var location: PublicProfile.Location?
            public var properties: AnyCodable
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

            public init(attributes: PublicProfile,
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

        public var attributes: Attributes
        public init(profile: PublicProfile, anonymousId: String) {
            attributes = Attributes(
                attributes: profile,
                anonymousId: anonymousId)
        }

        public init(attributes: Attributes) {
            self.attributes = attributes
        }
    }

    public var data: Profile
}
