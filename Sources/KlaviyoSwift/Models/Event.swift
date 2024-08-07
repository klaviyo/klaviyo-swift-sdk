//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/6/24.
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
        self.time = time ?? analytics.date()
        self.value = value
        self.uniqueId = uniqueId ?? analytics.uuid().uuidString
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
        time = analytics.date()
        self.uniqueId = uniqueId ?? analytics.uuid().uuidString
    }
}

extension Event.EventName {
    var value: String {
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
