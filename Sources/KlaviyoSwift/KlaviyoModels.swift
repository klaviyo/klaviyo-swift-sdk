//
//  KlaviyoModels.swift
//  
//
//  Created by Noah Durell on 11/25/22.
//

import Foundation
import AnyCodable

struct Event: Equatable {
    enum EventName: Equatable {
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
            case .CustomEvent(let value): return "\(value)"
            }
        }
    }
    struct Attributes: Equatable {
        struct Metric: Equatable {
            let name: EventName
            init(name: EventName) {
                self.name = name
            }
        }
        let metric: Metric
        var properties: [String: Any] {
            return _properties.value as! [String: Any]
        }
        private let _properties: AnyCodable
        var profile: [String: Any] {
            return _profile.value as! [String: Any]
        }
        private let _profile: AnyCodable
        var time: Date
        let value: Double?
        let uniqueId: String
        init(metric: Metric,
             properties: [String : Any],
             profile: [String : Any],
             value: Double? = nil,
             time: Date? = nil,
             uniqueId: String? = nil) {
            self._profile = AnyCodable(profile)
            self.metric = metric
            self._properties = AnyCodable(properties)
            self.value = value
            self.time = time ?? environment.analytics.date()
            self.uniqueId = uniqueId ?? environment.analytics.uuid().uuidString
        }
        
    }
    let attributes: Attributes
    init(attributes: Attributes) {
        self.attributes = attributes
    }
}

@_spi(KlaviyoPrivate)
public struct Profile: Equatable {
    @_spi(KlaviyoPrivate)
    public struct Attributes: Equatable {
        @_spi(KlaviyoPrivate)
        public struct Location: Equatable {
            let address1: String?
            let address2: String?
            let city: String?
            let country: String?
            let latitude: Double?
            let longitude: Double?
            let region: String?
            let zip: String?
            let timezone: String?
            init(address1: String?=nil,
                 address2: String?=nil,
                 city: String?=nil,
                 country: String?=nil,
                 latitude: Double?=nil,
                 longitude: Double?=nil,
                 region: String?=nil,
                 zip: String?=nil,
                 timezone: String?=nil) {
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
        let email: String?
        let phoneNumber: String?
        let externalId: String?
        let firstName: String?
        let lastName: String?
        let organization: String?
        let title: String?
        let image: String?
        let location: Location?
        var properties: [String: Any] {
            return _properties.value as! [String: Any]
        }
        let _properties: AnyCodable
        init(email: String?=nil,
             phoneNumber: String?=nil,
             externalId: String?=nil,
             firstName: String?=nil,
             lastName: String?=nil,
             organization: String?=nil,
             title: String?=nil,
             image: String?=nil,
             location: Location?=nil,
             properties: [String : Any]? = nil) {
            self.email = email
            self.phoneNumber = phoneNumber
            self.externalId = externalId
            self.firstName = firstName
            self.lastName = lastName
            self.organization = organization
            self.title = title
            self.image = image
            self.location = location
            self._properties = AnyCodable(properties ?? [:])
        }
    }
    let attributes: Attributes
    init(attributes: Attributes) {
        self.attributes = attributes
    }
}
