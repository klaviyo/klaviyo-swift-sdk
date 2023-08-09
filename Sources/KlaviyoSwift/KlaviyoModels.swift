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
        case ViewedProduct
        case SearchedProducts
        case StartedCheckout
        case PlacedOrder
        case OrderedProduct
        case CancelledOrder
        case PaidForOrder
        case SubscribedToBackInStock
        case SubscribedToComingSoon
        case SubscribedToList
        case SuccessfulPayment
        case FailedPayment
        case CustomEvent(String)
    }

    public struct Metric: Equatable {
        public let name: EventName

        public init(name: EventName) {
            self.name = name
        }
    }

    public struct Identifiers: Equatable {
        public let email: String?
        public let phoneNumber: String?
        public let externalId: String?
        init(email: String? = nil,
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
    public var profile: [String: Any] {
        _profile.value as! [String: Any]
    }

    internal var _profile: AnyCodable
    public var time: Date
    public let value: Double?
    public let uniqueId: String
    public let identifiers: Identifiers?

    public init(name: EventName,
                properties: [String: Any]? = nil,
                identifiers: Identifiers? = nil,
                profile: [String: Any]? = nil,
                value: Double? = nil,
                time: Date? = nil,
                uniqueId: String? = nil) {
        _profile = AnyCodable(profile ?? [:])
        metric = .init(name: name)
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

extension Event.EventName {
    var value: String {
        switch self {
        case .OpenedPush: return "$opened_push"
        case .ViewedProduct: return "$viewed_product"
        case .SearchedProducts: return "$searched_products"
        case .StartedCheckout: return "$started_checkout"
        case .PlacedOrder: return "$placed_order"
        case .OrderedProduct: return "$ordered_product"
        case .CancelledOrder: return "$cancelled_order"
        case .PaidForOrder: return "$paid_for_order"
        case .SubscribedToBackInStock: return "$subscribed_to_back_in_stock"
        case .SubscribedToComingSoon: return "$subscribed_to_coming_soon"
        case .SubscribedToList: return "$subscribed_to_list"
        case .SuccessfulPayment: return "$successful_payment"
        case .FailedPayment: return "$failed_payment"
        case let .CustomEvent(value): return "\(value)"
        }
    }
}
