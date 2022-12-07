//
//  InternalAPIModels.swift
//  Internal models typically used at the networking layer.
//
//  Created by Noah Durell on 11/25/22.
//

import Foundation
import AnyCodable

extension KlaviyoAPI.KlaviyoRequest {
    enum KlaviyoEndpoint: Equatable, Codable {
        struct CreateProfilePayload: Equatable, Codable {
            /**
             Internal structure which has details not needed by the API.
             */
            struct Profile: Equatable, Codable {
                let type = "profile"
                struct Attributes: Equatable, Codable {
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
                struct Meta: Equatable, Codable {
                    struct Identifiers: Equatable, Codable {
                        let email: String?
                        let phoneNumber: String?
                        let externalId: String?
                        let anonymousId: String?
                        init(attributes: Klaviyo.Profile.Attributes, anonymousId: String) {
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
        struct CreateEventPayload: Equatable, Codable {
            struct Event: Equatable, Codable {
                struct Attributes: Equatable, Codable {
                    struct Metric: Equatable, Codable {
                        let name: String
                        let service = "ios-analytics"
                        init(name: String) {
                            self.name = name
                        }
                        enum CodingKeys: CodingKey {
                            case name
                            case service
                        }
                    }
                    let metric: Metric
                    let properties: AnyCodable
                    let profile: AnyCodable
                    var time: Date
                    let value: Double?
                    let uniqueId: String
                    init(attributes: Klaviyo.Event.Attributes) {
                        self.profile = AnyCodable(attributes.profile)
                        self.metric = Metric(name: attributes.metric.name)
                        self.properties = AnyCodable(attributes.properties)
                        self.value = attributes.value
                        self.time = attributes.time
                        self.uniqueId = attributes.uniqueId
                    }
                    enum CodingKeys: CodingKey {
                        case metric
                        case properties
                        case profile
                        case time
                        case value
                        case uniqueId
                    }
                    
                }
                let type = "event"
                let attributes: Attributes
                init(event: Klaviyo.Event) {
                    self.attributes = .init(attributes: event.attributes)
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
        struct PushTokenPayload: Equatable, Codable {
            struct Properties: Equatable, Codable {
                let anonymousId: String
                let email: String?
                let phoneNumber: String?
                let pushToken: String?
                let externalId: String?
                
                enum CodingKeys: String, CodingKey {
                    case anonymousId = "$anonymous"
                    case email = "$email"
                    case phoneNumber = "$phone_number"
                    case pushToken = "$ios_tokens"
                    case externalId = "$id"
                }
                init(anonymousId: String,
                     pushToken: String,
                     email: String? = nil,
                     phoneNumber: String? = nil,
                     externalId: String? = nil
                ) {
                    self.email = email
                    self.phoneNumber = phoneNumber
                    self.anonymousId = anonymousId
                    self.pushToken = pushToken
                    self.externalId = externalId
                }
            }
            // This is actually the api key for this endpoint
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

    func encode(to encoder: Encoder) throws {
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


// MARK: Legacy request data

struct LegacyEvent {
     let eventName: String
     let customerProperties: NSDictionary
     let properties: NSDictionary
     init(eventName: String,
          customerProperties: NSDictionary?,
          properties: NSDictionary?) {
         self.eventName = eventName
         self.customerProperties = customerProperties ?? NSDictionary()
         self.properties = properties ?? NSDictionary()
     }
    func buildEventRequest(with apiKey: String) throws -> KlaviyoAPI.KlaviyoRequest? {
        guard let eventProperties = self.properties as? [String: Any] else {
            throw KlaviyoAPI.KlaviyoAPIError.invalidData
        }
        guard let customerProperties = self.customerProperties as? [String: Any] else {
            throw KlaviyoAPI.KlaviyoAPIError.invalidData
        }
        let payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload(data: .init(
            attributes: .init(metric: .init(name: self.eventName),
                              properties: eventProperties,
                              profile: customerProperties)))
        let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.createEvent(payload)
        return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
    }
}

 struct LegacyProfile {
     let customerProperties: NSDictionary
     
     func buildProfileRequest(with apiKey: String, from state: KlaviyoState) throws -> KlaviyoAPI.KlaviyoRequest? {
         guard var customerProperties = self.customerProperties as? [String: Any] else {
             throw KlaviyoAPI.KlaviyoAPIError.invalidData
         }
         
         guard let anonymousId = state.anonymousId else {
             throw KlaviyoAPI.KlaviyoAPIError.internalError("Unable to build request missing required anonymous id.")
         }
         
         // Migrate some legacy properties from properties to v3 API structure.
         let email: String? = customerProperties.removeValue(forKey: "$email") as? String ?? state.email
         let phoneNumber: String? = customerProperties.removeValue(forKey: "$phone_number") as? String ?? state.phoneNumber
         let externalId: String? = customerProperties.removeValue(forKey: "$id") as? String ?? state.externalId
         customerProperties.removeValue(forKey: "$anonymous") // Remove $anonymous since we are moving to a uuid (passed in above).
         let attributes = Klaviyo.Profile.Attributes(
             email: email,
             phoneNumber: phoneNumber,
             externalId: externalId,
             properties: customerProperties
         )
         let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.createProfile(.init(data: .init(profile: .init(attributes: attributes), anonymousId: anonymousId)))

         return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
     }
 }
