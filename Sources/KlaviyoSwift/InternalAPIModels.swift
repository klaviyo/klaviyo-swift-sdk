//
//  InternalAPIModels.swift
//  Internal models typically used at the networking layer.
//  NOTE: Ensure that new request types are equatable and encodable.
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
                var type = "profile"
                struct Attributes: Equatable, Codable {
                    let email: String?
                    let phoneNumber: String?
                    let externalId: String?
                    let anonymousId: String
                    let firstName: String?
                    let lastName: String?
                    let organization: String?
                    let title: String?
                    let image: String?
                    let location: KlaviyoSwift.Profile.Attributes.Location?
                    let properties: AnyCodable
                    enum CodingKeys: String, CodingKey {
                        case email
                        case phoneNumber = "phone_number"
                        case externalId = "external_id"
                        case anonymousId = "anonymous_id"
                        case firstName = "first_name"
                        case lastName = "last_name"
                        case organization
                        case title
                        case image
                        case location
                        case properties
                    }
                    init(attributes: KlaviyoSwift.Profile.Attributes,
                         anonymousId: String) {
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
                        let anonymousId: String
                        init(attributes: KlaviyoSwift.Profile.Attributes, anonymousId: String) {
                            self.email = attributes.email
                            self.phoneNumber = attributes.phoneNumber
                            self.externalId = attributes.externalId
                            self.anonymousId = anonymousId
                        }
                        enum CodingKeys: String, CodingKey {
                            case email
                            case phoneNumber = "phone_number"
                            case externalId = "external_id"
                            case anonymousId = "anonymous_id"
                        }
                    }
                    let identifiers: Identifiers
                }
                let attributes: Attributes
                let meta: Meta
                init(profile: KlaviyoSwift.Profile, anonymousId: String) {
                    self.attributes = Attributes(
                        attributes: profile.attributes,
                        anonymousId: anonymousId)
                    self.meta = Meta(identifiers: .init(
                        attributes: profile.attributes,
                        anonymousId: anonymousId))
                }
            }
            let data: Profile
        }
        struct CreateEventPayload: Equatable, Codable {
            struct Event: Equatable, Codable {
                struct Attributes: Equatable, Codable {
                    struct Metric: Equatable, Codable {
                        let name: String
                        init(name: String) {
                            self.name = name
                        }
                    }
                    let metric: Metric
                    let properties: AnyCodable
                    let profile: AnyCodable
                    let time: Date
                    let value: Double?
                    let uniqueId: String
                    init(attributes: KlaviyoSwift.Event.Attributes,
                         anonymousId: String? = nil) {
                        self.metric = Metric(name: attributes.metric.name.value)
                        self.properties = AnyCodable(attributes.properties)
                        self.value = attributes.value
                        self.time = attributes.time
                        self.uniqueId = attributes.uniqueId
                        if let anonymousId = anonymousId {
                            var updatedProfile = attributes.profile
                            updatedProfile["$anonymous"] = anonymousId
                            self.profile = AnyCodable(updatedProfile)
                        } else {
                            self.profile = AnyCodable(attributes.profile)
                        }
                    }
                    enum CodingKeys: String, CodingKey {
                        case metric
                        case properties
                        case profile
                        case time
                        case value
                        case uniqueId = "unique_id"
                    }
                    
                }
                var type = "event"
                let attributes: Attributes
                init(event: KlaviyoSwift.Event,
                     anonymousId: String? = nil) {
                    self.attributes = .init(attributes: event.attributes, anonymousId: anonymousId)
                }
            }
            let data: Event
            init(data: Event) {
                self.data = data
            }
        }
        struct PushTokenPayload: Equatable, Codable {
            struct Properties: Equatable, Codable {
                let anonymousId: String?
                let append: Append
                let email: String?
                let phoneNumber: String?
                let externalId: String?
                struct Append: Equatable, Codable {
                    let pushToken: String
                    enum CodingKeys: String, CodingKey {
                        case pushToken = "$ios_tokens"
                    }
                }
                enum CodingKeys: String, CodingKey {
                    case anonymousId = "$anonymous"
                    case email = "$email"
                    case phoneNumber = "$phone_number"
                    case append = "$append"
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
                    self.append = Append(pushToken: pushToken)
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
        }
        case createProfile(CreateProfilePayload)
        case createEvent(CreateEventPayload)
        case storePushToken(PushTokenPayload)
    }
}

extension Profile.Attributes.Location: Codable {
    public init(from decoder: Decoder) throws {
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


// MARK: Legacy request data

struct LegacyIdentifiers {
    let email: String?
    let phoneNumber: String?
    let externalId: String?
    
    static func extractFrom(from customerProperties: NSDictionary) -> LegacyIdentifiers? {
        guard let customerProperties = customerProperties as? [String: Any] else {
            return nil
        }
        let email = customerProperties["$email"] as? String
        let phoneNumber = customerProperties["$phone_number"] as? String
        let externalId = customerProperties["$id"] as? String
        
        return Self.init(email: email,
                         phoneNumber: phoneNumber,
                         externalId: externalId
        )
    }
}

struct LegacyEvent: Equatable {
    let eventName: String
    let customerProperties: NSDictionary
    let properties: NSDictionary
    var identifiers: LegacyIdentifiers? {
        return LegacyIdentifiers.extractFrom(from: customerProperties)
    }
    
     init(eventName: String,
          customerProperties: NSDictionary?,
          properties: NSDictionary?) {
         self.eventName = eventName
         self.customerProperties = customerProperties ?? NSDictionary()
         self.properties = properties ?? NSDictionary()
     }
    func buildEventRequest(with apiKey: String, from state: KlaviyoState) throws -> KlaviyoAPI.KlaviyoRequest? {
        guard var eventProperties = self.properties as? [String: Any] else {
            throw KlaviyoAPI.KlaviyoAPIError.invalidData
        }
        guard var customerProperties = customerProperties as? [String: Any] else {
            throw KlaviyoAPI.KlaviyoAPIError.invalidData
        }
        
        // v3 events api still uses these properties - we are just ensuring we are using the latest
        // identifiers here.
        customerProperties["$email"] = state.email
        customerProperties["$phone_number"] = state.phoneNumber
        customerProperties["$id"] =  state.externalId
        customerProperties["$anonymous"] =  state.anonymousId
        if eventName == "$opened_push" {
            // Special handling for $opened_push include push token at the time of open
            eventProperties["push_token"] = state.pushToken
        }
        let event = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload.Event(event: .init(attributes: .init(metric: .init(name: .CustomEvent(self.eventName)), properties: eventProperties, profile: customerProperties)))
        let payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload.init(data: event)
        let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.createEvent(payload)
        return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
    }
}

struct LegacyProfile: Equatable {
     let customerProperties: NSDictionary
    
    var identifiers: LegacyIdentifiers? {
        return LegacyIdentifiers.extractFrom(from: customerProperties)
    }
     
     func buildProfileRequest(with apiKey: String, from state: KlaviyoState) throws -> KlaviyoAPI.KlaviyoRequest? {
         guard var customerProperties = self.customerProperties.copy() as? [String: Any] else {
             throw KlaviyoAPI.KlaviyoAPIError.invalidData
         }
         
         guard let anonymousId = state.anonymousId else {
             throw KlaviyoAPI.KlaviyoAPIError.internalError("Unable to build request missing required anonymous id.")
         }
         
         // Remove properties that are now strongly typed on the v3 request
         customerProperties.removeValue(forKey: "$email")
         customerProperties.removeValue(forKey: "$phone_number")
         customerProperties.removeValue(forKey: "$id")
         customerProperties.removeValue(forKey: "$anonymous")
         
         // We assume that the state has the latest identifiers
         let attributes = KlaviyoSwift.Profile.Attributes(
            email: state.email,
            phoneNumber: state.phoneNumber,
            externalId: state.externalId,
            properties: customerProperties
         )
         let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.createProfile(
            .init(data: .init(profile:
                    .init(attributes: attributes),
                              anonymousId: anonymousId)))

         return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
     }
 }
