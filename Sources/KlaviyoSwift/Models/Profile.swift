//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/6/24.
//

import AnyCodable
import Foundation

public struct Profile: Equatable {
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

    public struct Location: Equatable {
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
            self.timezone = timezone ?? analytics.timeZone()
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
