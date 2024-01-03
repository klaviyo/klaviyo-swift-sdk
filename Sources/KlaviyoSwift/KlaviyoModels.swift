//
//  KlaviyoModels.swift
//
//
//  Created by Noah Durell on 11/25/22.
//

import AnyCodable
import Foundation

public protocol MetricNameProtocol {
    var value: String { get }
}

public struct Event: Equatable {
    public struct Legacy: Equatable {
        public enum MetricName: MetricNameProtocol {
            case OpenedPush
            case ViewedProduct
            case StartedCheckout
            case OpenedApp
            case AddedToCart
            case CustomEvent(String)
        }
    }

    public struct V1: Equatable {
        public enum MetricName: MetricNameProtocol {
            case OpenedPush
            case ViewedProduct
            case StartedCheckout
            case OpenedApp
            case AddedToCart
            case CustomEvent(String)
        }
    }

    public struct Identifiers: Equatable {
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

    public struct Metric: Equatable {
        public static func ==(lhs: Event.Metric, rhs: Event.Metric) -> Bool {
            type(of: lhs.metricName) == type(of: rhs.metricName)
                && lhs.metricName.value == rhs.metricName.value
        }

        public var metricName: any MetricNameProtocol
    }

    public let metric: Metric
    public var properties: [String: Any] {
        _properties.value as! [String: Any]
    }

    private let _properties: AnyCodable
    public var profile: [String: Any] {
        _profile.value as? [String: Any] ?? [:]
    }

    internal var _profile: AnyCodable
    public var time: Date
    public let value: Double?
    public let uniqueId: String
    public let identifiers: Identifiers?

    public init(name: any MetricNameProtocol,
                properties: [String: Any]? = nil,
                identifiers: Identifiers? = nil,
                profile: [String: Any]? = nil,
                value: Double? = nil,
                time: Date? = nil,
                uniqueId: String? = nil) {
        var profile = profile
        let email = profile?.removeValue(forKey: "$email") as? String
        let phoneNumber = profile?.removeValue(forKey: "$phone_number") as? String
        let externalId = profile?.removeValue(forKey: "$id") as? String
        // identifiers takes precendence if available otherwise fallback to profile.
        let identifiers = identifiers ?? Identifiers(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId)
        _profile = AnyCodable(profile)
        metric = Metric(metricName: name)
        _properties = AnyCodable(properties ?? [:])
        self.value = value
        self.time = time ?? environment.analytics.date()
        self.uniqueId = uniqueId ?? environment.analytics.uuid().uuidString
        self.identifiers = identifiers
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

extension Event.Legacy.MetricName {
    public var value: String {
        switch self {
        case .OpenedPush: return "$opened_push"
        case .ViewedProduct: return "$viewed_product"
        case .StartedCheckout: return "$started_checkout"
        case .AddedToCart: return "$added_to_cart"
        case .OpenedApp: return "$opened_app"
        case let .CustomEvent(value): return "\(value)"
        }
    }
}

extension Event.V1.MetricName {
    public var value: String {
        switch self {
        case .OpenedPush: return "$opened_push"
        case .ViewedProduct: return "Viewed Product"
        case .StartedCheckout: return "Started Checkout"
        case .AddedToCart: return "Added to Cart"
        case .OpenedApp: return "Opened App"
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
