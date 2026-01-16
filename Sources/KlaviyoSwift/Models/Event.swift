//
//  Event.swift
//
//
//  Created by Ajay Subramanya on 8/6/24.
//

import AnyCodable
import Foundation
import KlaviyoCore

public struct Event: Equatable {
    public enum EventName: Equatable, Hashable {
        case openedAppMetric
        case viewedProductMetric
        case addedToCartMetric
        case startedCheckoutMetric
        case locationEvent(LocationEvent)
        case customEvent(String)

        internal static var _openedPush: EventName {
            EventName.customEvent("_openedPush")
        }

        public enum LocationEvent: Equatable {
            case geofenceEnter
            case geofenceExit
            case geofenceDwell
        }
    }

    public struct Metric: Equatable {
        public let name: EventName

        public init(name: EventName) {
            self.name = name
        }

        /// Returns true if this event is a geofence-related event
        public var isGeofenceEvent: Bool {
            if case .locationEvent = name { true } else { false }
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
    public let time: Date
    public let value: Double?
    public let uniqueId: String
    let identifiers: Identifiers?

    init(name: EventName,
         properties: [String: Any]? = nil,
         identifiers: Identifiers? = nil,
         value: Double? = nil,
         time: Date = environment.date(),
         uniqueId: String = environment.uuid().uuidString) {
        metric = .init(name: name)
        _properties = AnyCodable(properties ?? [:])
        self.time = time
        self.value = value
        self.uniqueId = uniqueId
        self.identifiers = identifiers
    }

    /// Create a new event to track a profile's activity, the SDK will associate the event with any identified/anonymous profile in the SDK state
    /// - Parameters:
    ///   - name: Name of the event. Must be less than 128 characters., pick from ``Event.EventName`` which can also contain custom events
    ///   - properties: Properties of this event.
    ///   - value: A numeric, monetary value to associate with this event. For example, the dollar amount of a purchase.
    ///   - uniqueId: A unique identifier for an event
    public init(name: EventName,
                properties: [String: Any]? = nil,
                value: Double? = nil,
                uniqueId: String? = nil) {
        metric = .init(name: name)
        _properties = AnyCodable(properties ?? [:])
        identifiers = nil
        self.value = value
        time = environment.date()
        self.uniqueId = uniqueId ?? environment.uuid().uuidString
    }
}

extension Event.EventName {
    public var value: String {
        switch self {
        case ._openedPush: return "$opened_push"
        case .openedAppMetric: return "Opened App"
        case .viewedProductMetric: return "Viewed Product"
        case .addedToCartMetric: return "Added to Cart"
        case .startedCheckoutMetric: return "Started Checkout"
        case let .locationEvent(type):
            switch type {
            case .geofenceEnter:
                return "$geofence_enter"
            case .geofenceExit:
                return "$geofence_exit"
            case .geofenceDwell:
                return "$geofence_dwell"
            }
        case let .customEvent(value): return "\(value)"
        }
    }
}
