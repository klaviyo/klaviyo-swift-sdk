//
//  KlaviyoModels.swift
//  
//
//  Created by Noah Durell on 11/25/22.
//

import Foundation

extension Klaviyo {
    /**
     ND: Marking this all as internal until we finalize our API.
     */
    struct Event {
        struct Attributes {
            struct Metric {
                let name: String
                let service: String?
                init(name: String,
                     service: String?="ios-analytics") {
                    self.name = name
                    self.service = service
                }
            }
            let metric: Metric
            let properties: [String: Any]
            let profile: [String: Any]
            var time: Date?
            let value: Double?
            let uniqueId: String
            init(metric: Metric,
                 properties: [String : Any],
                 profile: [String : Any],
                 value: Double? = nil,
                 time: Date? = nil,
                 uniqueId: String? = nil) {
                self.profile = profile
                self.metric = metric
                self.properties = properties
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
    
    struct Profile {
        struct Attributes {
            struct Location {
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
                     timezone: String?=TimeZone.autoupdatingCurrent.identifier) {
                    self.address1 = address1
                    self.address2 = address2
                    self.city = city
                    self.country = country
                    self.latitude = latitude
                    self.longitude = longitude
                    self.region = region
                    self.zip = zip
                    self.timezone = timezone
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
            let properties: [String: Any]?
            init(email: String?=nil,
                 phoneNumber: String?=nil,
                 externalId: String?=nil,
                 firstName: String?=nil,
                 lastName: String?=nil,
                 organization: String?=nil,
                 title: String?=nil,
                 image: String?=nil,
                 location: Location?=nil,
                 properties: [String : Any]?=nil) {
                self.email = email
                self.phoneNumber = phoneNumber
                self.externalId = externalId
                self.firstName = firstName
                self.lastName = lastName
                self.organization = organization
                self.title = title
                self.image = image
                self.location = location
                self.properties = properties
            }
        }
        let attributes: Attributes
        init(attributes: Attributes) {
            self.attributes = attributes
        }
    }
    
}
