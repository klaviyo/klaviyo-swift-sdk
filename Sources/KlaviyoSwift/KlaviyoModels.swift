//
//  KlaviyoModels.swift
//
//
//  Created by Noah Durell on 11/25/22.
//

import AnyCodable
import Foundation

public struct Event: Equatable {
    public enum EventName: Equatable {
        case OpenedPush
        case OpenedAppMetric
        case ViewedProductMetric
        case AddedToCartMetric
        case StartedCheckoutMetric
        case CustomEvent(String)
    }

    public struct Metric: Equatable {
        public let name: EventName

        public init(name: EventName) {
            self.name = name
        }
    }

    struct Identifiers: Equatable {
        public let email: String?
        public let phoneNumber: String?
        public let externalId: String?
        public init(email: String? = nil,
                    phoneNumber: String? = nil,
                    externalId: String? = nil) {
            self.email = email
            self.phoneNumber = phoneNumber
            self.externalId = externalId
        }
    }

    public let metric: Metric
    public var properties: [String: Any] {
        _properties.value as! [String: Any]
    }

    private let _properties: AnyCodable
    public var time: Date
    public let value: Double?
    public let uniqueId: String
    let identifiers: Identifiers?

    init(name: EventName,
         properties: [String: Any]? = nil,
         identifiers: Identifiers? = nil,
         value: Double? = nil,
         time: Date? = nil,
         uniqueId: String? = nil) {
        metric = .init(name: name)
        _properties = AnyCodable(properties ?? [:])
        self.time = time ?? environment.analytics.date()
        self.value = value
        self.uniqueId = uniqueId ?? environment.analytics.uuid().uuidString
        self.identifiers = identifiers
    }

    public init(name: EventName,
                properties: [String: Any]? = nil,
                value: Double? = nil,
                uniqueId: String? = nil) {
        metric = .init(name: name)
        _properties = AnyCodable(properties ?? [:])
        identifiers = nil
        self.value = value
        time = environment.analytics.date()
        self.uniqueId = uniqueId ?? environment.analytics.uuid().uuidString
    }
}

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
            self.timezone = timezone ?? environment.analytics.timeZone()
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

extension Event.EventName {
    public var value: String {
        switch self {
        case .OpenedPush: return "$opened_push"
        case .OpenedAppMetric: return "Opened App"
        case .ViewedProductMetric: return "Viewed Product"
        case .AddedToCartMetric: return "Added to Cart"
        case .StartedCheckoutMetric: return "Started Checkout"
        case let .CustomEvent(value): return "\(value)"
        }
    }
}

struct ErrorResponse: Codable {
    let errors: [ErrorDetail]
}

struct ErrorDetail: Codable {
    let id: String
    let status: Int
    let code: String
    let title: String
    let detail: String
    let source: ErrorSource
}

struct ErrorSource: Codable {
    let pointer: String
}
