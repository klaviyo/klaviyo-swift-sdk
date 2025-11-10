//
//  Profile.swift
//
//
//  Created by Ajay Subramanya on 8/6/24.
//

import AnyCodable
import Foundation
import KlaviyoCore

public struct Profile: Equatable, Codable {
    public enum ProfileKey: Equatable, Hashable, Codable {
        case firstName
        case lastName
        case address1
        case address2
        case title
        case organization
        case city
        case region
        case country
        case zip
        case image
        case latitude
        case longitude
        case custom(customKey: String)
    }

    public struct Location: Equatable, Codable {
        public var address1: String?
        public var address2: String?
        public var city: String?
        public var country: String?
        public var latitude: Double?
        public var longitude: Double?
        public var region: String?
        public var zip: String?
        public var timezone: String?

        /// - Parameters:
        ///   - address1: First line of street address
        ///   - address2: Second line of street address
        ///   - city: city name
        ///   - country: country name
        ///   - latitude: Latitude coordinate. We recommend providing a precision of four decimal places.
        ///   - longitude: Longitude coordinate. We recommend providing a precision of four decimal places.
        ///   - region: Region within a country, such as state or province
        ///   - zip: Zip code
        ///   - timezone: Time zone name. We recommend using time zones from the IANA Time Zone Database.
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

    public let email: String?
    public let phoneNumber: String?
    public let externalId: String?
    public let firstName: String?
    public let lastName: String?
    public let organization: String?
    public let title: String?
    public let image: String?
    public let location: Location?
    public var properties: [String: Any] {
        _properties.value as! [String: Any]
    }

    let _properties: AnyCodable

    /// Create or update properties about a profile without tracking an associated event.
    /// - Parameters:
    ///   - email: Individual's email address
    ///   - phoneNumber: Individual's phone number in E.164 format
    ///   - externalId: A unique identifier used by customers to associate Klaviyo profiles with profiles in an external system, such as a point-of-sale system. Format varies based on the external system.
    ///   - firstName: Individual's first name
    ///   - lastName: Individual's last name
    ///   - organization: Individual's organization name
    ///   - title: Individual's title
    ///   - image: URL pointing to the location of a profile image
    ///   - location: Individual location
    ///   - properties: An object containing key/value pairs for any custom properties assigned to this profile
    public init(email: String? = nil,
                phoneNumber: String? = nil,
                externalId: String? = nil,
                firstName: String? = nil,
                lastName: String? = nil,
                organization: String? = nil,
                title: String? = nil,
                image: String? = nil,
                location: Location? = nil,
                properties: [String: Any]? = nil) {
        self.email = email
        self.phoneNumber = phoneNumber
        self.externalId = externalId
        self.firstName = firstName
        self.lastName = lastName
        self.organization = organization
        self.title = title
        self.image = image
        self.location = location
        _properties = AnyCodable(properties ?? [:])
    }
}
