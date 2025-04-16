//
//  ProfilePayload.swift
//
//
//  Created by Ajay Subramanya on 8/6/24.
//

import Foundation
import KlaviyoSDKDependencies

/**
 Internal structure which has details not needed by the API.
 */
public struct ProfilePayload: Equatable, Codable, Sendable {
    var type = "profile"
    public struct Attributes: Equatable, Codable, Sendable {
        public let anonymousId: String
        public let email: String?
        public let phoneNumber: String?
        public let externalId: String?
        public var firstName: String?
        public var lastName: String?
        public var organization: String?
        public var title: String?
        public var image: String?
        public var location: Location?
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

        public init(email: String? = nil,
                    phoneNumber: String? = nil,
                    externalId: String? = nil,
                    firstName: String? = nil,
                    lastName: String? = nil,
                    organization: String? = nil,
                    title: String? = nil,
                    image: String? = nil,
                    location: Location? = nil,
                    properties: [String: Any]? = nil,
                    anonymousId: String) {
            self.email = email
            self.phoneNumber = phoneNumber
            self.externalId = externalId
            self.firstName = firstName
            self.lastName = lastName
            self.organization = organization
            self.title = title
            self.image = image
            self.location = location
            self.properties = AnyCodable(properties ?? [:])
            self.anonymousId = anonymousId
        }

        public struct Location: Equatable, Codable, Sendable {
            public var address1: String?
            public var address2: String?
            public var city: String?
            public var country: String?
            public var latitude: Double?
            public var longitude: Double?
            public var region: String?
            public var zip: String?
            public var timezone: String?

            public init(address1: String? = nil,
                        address2: String? = nil,
                        city: String? = nil,
                        country: String? = nil,
                        latitude: Double? = nil,
                        longitude: Double? = nil,
                        region: String? = nil,
                        zip: String? = nil,
                        timezone: String? = nil) {
                self.address1 = address1
                self.address2 = address2
                self.city = city
                self.country = country
                self.latitude = latitude
                self.longitude = longitude
                self.region = region
                self.zip = zip
                self.timezone = timezone ?? environment.timeZone()
            }
        }
    }

    public var attributes: Attributes

    public init(email: String? = nil,
                phoneNumber: String? = nil,
                externalId: String? = nil,
                firstName: String? = nil,
                lastName: String? = nil,
                organization: String? = nil,
                title: String? = nil,
                image: String? = nil,
                location: Attributes.Location? = nil,
                properties: [String: Any]? = nil,
                anonymousId: String) {
        attributes = Attributes(
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
            anonymousId: anonymousId
        )
    }

    public init(attributes: Attributes) {
        self.attributes = attributes
    }
}
