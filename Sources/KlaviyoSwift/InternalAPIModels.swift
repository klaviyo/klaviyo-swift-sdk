//
//  InternalAPIModels.swift
//  Internal models typically used at the networking layer.
//
//  Created by Noah Durell on 11/25/22.
//

import Foundation
import AnyCodable

extension KlaviyoAPI.KlaviyoRequest {
    enum KlaviyoEndpoint: Codable {
        struct CreateProfilePayload: Codable {
            /**
             Internal structure which has details not needed by the public API.
             */
            struct Profile: Codable {
                let type = "profile"
                struct Attributes: Codable {
                    let email: String?
                    let phoneNumber: String?
                    let externalId: String?
                    let anonymousId: String?
                    let firstName: String?
                    let lastName: String?
                    let organization: String?
                    let title: String?
                    let image: String?
                    let location: Klaviyo.Profile.Attributes.Location?
                    let properties: AnyCodable
                    enum CodingKeys: String, CodingKey {
                        case email
                        case phoneNumber
                        case externalId
                        case anonymousId
                        case firstName
                        case lastName
                        case organization
                        case title
                        case image
                        case location
                        case properties
                    }
                    init(attributes: Klaviyo.Profile.Attributes, anonymousId: String) {
                        self.email = attributes.email
                        self.phoneNumber = attributes.phoneNumber
                        self.externalId = attributes.externalId
                        self.firstName = attributes.firstName
                        self.lastName = attributes.lastName
                        self.organization = attributes.organization
                        self.title = attributes.title
                        self.image = attributes.image
                        self.location = attributes.location
                        self.properties = AnyCodable(attributes.properties)
                        self.anonymousId = anonymousId
                    }
                    
                }
                struct Meta: Codable {
                    struct Identifiers: Codable {
                        let email: String?
                        let phoneNumber: String?
                        let externalId: String?
                        let anonymousId: String?
                        public init(attributes: Klaviyo.Profile.Attributes, anonymousId: String) {
                            self.email = attributes.email
                            self.phoneNumber = attributes.phoneNumber
                            self.externalId = attributes.externalId
                            self.anonymousId = anonymousId
                        }
                        enum CodingKeys: String, CodingKey {
                            case email
                            case phoneNumber
                            case externalId
                            case anonymousId
                        }
                    }
                    let identifiers: Identifiers
                    enum CodingKeys: String, CodingKey {
                        case identifiers
                    }
                }
                let attributes: Attributes
                let meta: Meta
                init(profile: Klaviyo.Profile, anonymousId: String) {
                    self.attributes = Attributes(
                        attributes: profile.attributes,
                        anonymousId: anonymousId)
                    self.meta = Meta(identifiers: .init(
                        attributes: profile.attributes,
                        anonymousId: anonymousId))
                }
                
                enum CodingKeys: String, CodingKey {
                    case attributes
                    case meta
                    case type
                }
            }
            let data: Profile
            
            enum CodingKeys: String, CodingKey {
                case data
            }
        }
        struct CreateEventPayload: Codable {
            struct Event: Codable {
                let type = "event"
                let attributes: Klaviyo.Event.Attributes
                init(event: Klaviyo.Event) {
                    self.attributes = event.attributes
                }
                enum CodingKeys: CodingKey {
                    case attributes
                    case type
                }
            }
            let data: Event
            enum CodingKeys: CodingKey {
                case data
            }
            init(data: Klaviyo.Event) {
                self.data = Event(event: data)
            }
        }
        struct PushTokenPayload: Codable {
            struct Properties: Codable {
                public let email: String?
                public let phoneNumber: String?
                public let anonymousId: String
                public let pushToken: String
                
                enum CodingKeys: String, CodingKey {
                    case email = "$email"
                    case phoneNumber = "$phone_number"
                    case anonymousId = "$anonymous"
                    case pushToken = "$ios_tokens"
                }
                init(anonymousId: String,
                     pushToken: String,
                     email: String? = nil,
                     phoneNumber: String? = nil
                ) {
                    self.email = email
                    self.phoneNumber = phoneNumber
                    self.anonymousId = anonymousId
                    self.pushToken = pushToken
                }
            }
            let token: String
            let properties: Properties
            init(token: String,
                 properties: Properties) {
                self.token = token
                self.properties = properties
            }
            enum CodingKeys: String, CodingKey {
                case token
                case properties
            }
        }
        case createProfile(CreateProfilePayload)
        case createEvent(CreateEventPayload)
        case storePushToken(PushTokenPayload)
    }
}

extension Klaviyo.Profile.Attributes.Location: Codable {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.address1 = try values.decode(String.self, forKey: .address1)
        self.address2 = try values.decode(String.self, forKey: .address2)
        self.city = try values.decode(String.self, forKey: .city)
        self.latitude = try values.decode(Double.self, forKey: .latitude)
        self.longitude = try values.decode(Double.self, forKey: .longitude)
        self.region = try values.decode(String.self, forKey: .region)
        self.zip = try values.decode(String.self, forKey: .zip)
        self.timezone = try values.decode(String.self, forKey: .timezone)
        self.country = try values.decode(String.self, forKey: .country)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address1, forKey: .address1)
        try container.encode(address2, forKey: .address2)
        try container.encode(city, forKey: .city)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(region, forKey: .region)
        try container.encode(zip, forKey: .zip)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(country, forKey: .country)
    }
    
    enum CodingKeys: CodingKey {
        case address1
        case address2
        case city
        case country
        case latitude
        case longitude
        case region
        case zip
        case timezone
    }
}

/**
 Encoding
 */

extension Klaviyo.Event: Encodable {
    enum CodingKeys: CodingKey {
        case attributes
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(attributes, forKey: .attributes)
    }
}

extension Klaviyo.Event.Attributes.Metric: Codable {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
//        self.service = try values.decode(String.self, forKey: .service)
        self.name = try values.decode(String.self, forKey: .name)
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case service
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(service, forKey: .service)
    }

}

extension Klaviyo.Event.Attributes: Codable {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.metric = try values.decode(Metric.self, forKey: .metric)
        self.properties = try values.decode([String: AnyCodable].self, forKey: .properties)
        self.profile = try values.decode([String: AnyCodable].self, forKey: .profile)
        self.time = try values.decode(Date.self, forKey: .time)
        self.value = try values.decode(Double.self, forKey: .value)
        self.uniqueId = try values.decode(String.self, forKey: .uniqueId)
        
    }
    
    enum CodingKeys: CodingKey {
        case metric
        case properties
        case profile
        case time
        case value
        case uniqueId
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metric, forKey: .metric)
        try container.encode(AnyCodable(properties), forKey: .properties)
        try container.encode(AnyCodable(profile), forKey: .profile)
        try container.encode(time, forKey: .time)
        try container.encode(value, forKey: .value)
        try container.encode(uniqueId, forKey: .uniqueId)
    }
}

