//
//  InternalAPIModels.swift
//  
//
//  Created by Noah Durell on 11/25/22.
//

import Foundation
import AnyCodable

extension KlaviyoAPI.KlaviyoRequest {
    enum KlaviyoEndpoint: Encodable {
        struct CreateProfilePayload: Encodable {
            /**
             Internal structure which has details not needed by the public API.
             */
            struct Profile: Encodable {
                let type = "profile"
                struct Attributes: Encodable {
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
                    let properties: AnyEncodable
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
                        self.properties = AnyEncodable(attributes.properties)
                        self.anonymousId = anonymousId
                    }
                    
                }
                struct Meta: Encodable {
                    struct Identifiers: Encodable {
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
                    enum CodingKeys: CodingKey {
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
                
                enum CodingKeys: CodingKey {
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
        struct CreateEventPayload: Encodable {
            struct Event: Encodable {
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
        struct PushTokenPayload: Encodable {
            struct Properties: Encodable {
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
        }
        case createProfile(CreateProfilePayload)
        case createEvent(CreateEventPayload)
        case storePushToken(PushTokenPayload)
    }
}

extension KlaviyoAPI.KlaviyoRequest {
    func urlRequest() throws -> URLRequest {
        guard let url = self.url else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("Invalid url string. API URL: \(environment.analytics.apiURL)")
        }
        var request = URLRequest(url: url)
        // We only support post right now
        guard let body = try? self.encodeBody() else {
            throw KlaviyoAPI.KlaviyoAPIError.dataEncodingError(self)
        }
        request.httpBody = body
        request.httpMethod = "POST"
        
        return request
        
    }
    
    var url: URL? {
        switch self.endpoint {
        case .createProfile, .createEvent:
            return URL(string: "\(environment.analytics.apiURL)/\(path)/?company_id=\(self.apiKey)")
        case .storePushToken:
            return URL(string: "\(environment.analytics.apiURL)/\(path)")
        }
    }
                            
    var path: String {
        switch self.endpoint {
        case .createProfile:
            return "client/profiles"
        case .createEvent:
            return "client/events"
        case .storePushToken:
            return "api/identify"
        }
    }
    
    func encodeBody() throws -> Data {
        switch self.endpoint {
        case .createProfile(let payload):
            return try environment.analytics.encodeJSON(payload)
        case .createEvent(let payload):
            return try environment.analytics.encodeJSON(payload)
        case .storePushToken(let payload):
            return try environment.analytics.encodeJSON(payload)
        }
    }
}

extension Klaviyo.Profile.Attributes.Location: Encodable {
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

extension Klaviyo.Event.Attributes.Metric: Encodable {
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

extension Klaviyo.Event.Attributes: Encodable {
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
        try container.encode(AnyEncodable(properties), forKey: .properties)
        try container.encode(AnyEncodable(profile), forKey: .profile)
        try container.encode(time, forKey: .time)
        try container.encode(value, forKey: .value)
        try container.encode(uniqueId, forKey: .uniqueId)
    }
}

