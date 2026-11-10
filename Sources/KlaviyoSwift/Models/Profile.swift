//
//  Profile.swift
//
//
//  Created by Ajay Subramanya on 8/6/24.
//

import AnyCodable
import Foundation
import KlaviyoCore

/// The identifiers and attributes of a Klaviyo profile.
///
/// Pass a profile to ``KlaviyoSDK/set(profile:)`` to identify the current user and update their
/// attributes in one call:
///
/// ```swift
/// let profile = Profile(
///     email: "jane@example.com",
///     phoneNumber: "+15555550100",
///     externalId: "user-123",
///     firstName: "Jane",
///     lastName: "Doe",
///     location: Profile.Location(city: "Boston", country: "United States"),
///     properties: ["Loyalty Tier": "Gold"]
/// )
/// KlaviyoSDK().set(profile: profile)
/// ```
///
/// To set a single attribute instead, use ``KlaviyoSDK/set(profileAttribute:value:)`` with a
/// ``ProfileKey``.
public struct Profile: Equatable, Codable {
    /// A profile attribute you can set with ``KlaviyoSDK/set(profileAttribute:value:)``.
    public enum ProfileKey: Equatable, Hashable, Codable {
        /// The profile's first name. Takes a `String`.
        case firstName
        /// The profile's last name. Takes a `String`.
        case lastName
        /// The first line of the profile's street address. Takes a `String`.
        case address1
        /// The second line of the profile's street address. Takes a `String`.
        case address2
        /// The profile's job title. Takes a `String`.
        case title
        /// The name of the profile's organization. Takes a `String`.
        case organization
        /// The profile's city. Takes a `String`.
        case city
        /// The profile's region within a country, such as a state or province. Takes a `String`.
        case region
        /// The profile's country. Takes a `String`.
        case country
        /// The profile's zip or postal code. Takes a `String`.
        case zip
        /// The URL of the profile's image. Takes a `String`.
        case image
        /// The latitude of the profile's location. Takes a `Double`.
        case latitude
        /// The longitude of the profile's location. Takes a `Double`.
        case longitude
        /// A custom profile property.
        ///
        /// - Parameter customKey: The custom property's name.
        case custom(customKey: String)
    }

    /// The location attributes of a profile.
    public struct Location: Equatable, Codable {
        /// The first line of the street address.
        public var address1: String?
        /// The second line of the street address.
        public var address2: String?
        /// The city name.
        public var city: String?
        /// The country name.
        public var country: String?
        /// The latitude coordinate.
        public var latitude: Double?
        /// The longitude coordinate.
        public var longitude: Double?
        /// The region within the country, such as a state or province.
        public var region: String?
        /// The zip or postal code.
        public var zip: String?
        /// The time zone name, from the IANA Time Zone Database (for example, `America/New_York`).
        public var timezone: String?

        /// Creates a location.
        ///
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
        ///     Defaults to the device's current time zone.
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

    /// The profile's email address.
    public let email: String?
    /// The profile's phone number, in a format Klaviyo accepts, such as E.164.
    public let phoneNumber: String?
    /// An identifier for the profile from a system outside Klaviyo, such as your backend's user ID.
    public let externalId: String?
    /// The profile's first name.
    public let firstName: String?
    /// The profile's last name.
    public let lastName: String?
    /// The name of the profile's organization.
    public let organization: String?
    /// The profile's job title.
    public let title: String?
    /// The URL of the profile's image.
    public let image: String?
    /// The profile's location.
    public let location: Location?
    /// The profile's custom properties, keyed by property name.
    public var properties: [String: Any] {
        _properties.value as! [String: Any]
    }

    let _properties: AnyCodable

    /// Returns `true` if the profile contains any data beyond the three identifier fields
    /// (email, phoneNumber, externalId). Used to decide whether to skip a redundant API
    /// call when the caller's identifiers haven't changed.
    var hasNonIdentifierData: Bool {
        self != Profile(email: email, phoneNumber: phoneNumber, externalId: externalId)
    }

    /// Creates a profile.
    ///
    /// Every argument is optional. When you pass the profile to ``KlaviyoSDK/set(profile:)``, an
    /// identifier you leave out counts as removed, so include every identifier the profile has.
    ///
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

extension Profile {
    static func updateProfileWithProperties(
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        dict: [Profile.ProfileKey: AnyEncodable]
    ) -> Self {
        var firstName: String?
        var lastName: String?
        var address1: String?
        var address2: String?
        var title: String?
        var organization: String?
        var city: String?
        var region: String?
        var country: String?
        var zip: String?
        var image: String?
        var latitude: Double?
        var longitude: Double?
        var customProperties: [String: Any] = [:]

        for (key, value) in dict {
            switch key {
            case .firstName:
                firstName = value.value as? String
            case .lastName:
                lastName = value.value as? String
            case .address1:
                address1 = value.value as? String
            case .address2:
                address2 = value.value as? String
            case .title:
                title = value.value as? String
            case .organization:
                organization = value.value as? String
            case .city:
                city = value.value as? String
            case .region:
                region = value.value as? String
            case .country:
                country = value.value as? String
            case .zip:
                zip = value.value as? String
            case .image:
                image = value.value as? String
            case .latitude:
                latitude = value.value as? Double
            case .longitude:
                longitude = value.value as? Double
            case let .custom(customKey: customKey):
                customProperties[customKey] = value.value
            }
        }

        let location = Profile.Location(
            address1: address1,
            address2: address2,
            city: city,
            country: country,
            latitude: latitude,
            longitude: longitude,
            region: region,
            zip: zip
        )

        let profile = Profile(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            firstName: firstName,
            lastName: lastName,
            organization: organization,
            title: title,
            image: image,
            location: location,
            properties: customProperties
        )

        return profile
    }
}
