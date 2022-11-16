//
//  KlaviyoAPI.swift
//  
//
//  Created by Noah Durell on 11/8/22.
//

import Foundation


struct KlaviyoAPI {
    struct KlaviyoRequest {
      enum KlaviyoEndpoint {
          struct CreateProfilePayload: Encodable {
              /**
               Internal structure which details not needed by the public API.
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
          case createProfile(CreateProfilePayload)
          case createEvent(CreateEventPayload)
          case legacyIdentify
      }
      let apiKey: String
      let endpoint: KlaviyoEndpoint
    }
    enum HTTPMethod {
        case post
        case get
    }
    enum KlaviyoAPIError: Error {
        case httpError(Int, Data?)
        case rateLimitError
        case missingOrInvalidResponse(URLResponse?)
        case networkError(Error)
        case internalError(String)
        case internalRequestError(Error)
        case unknownError(Error)
        case dataEncodingError(KlaviyoRequest)
        case invalidData
    }
    var post: (KlaviyoRequest, @escaping (Result<Data, KlaviyoAPIError>) -> Void) -> Void = { request, result in
        var urlRequest: URLRequest
        do {
            urlRequest = try request.urlRequest()
        } catch {
            result(.failure(.internalRequestError(error)))
            return
        }
        environment.networkSession.dataTask(urlRequest) { data, response, error in
            if let networkError = error {
                result(.failure(KlaviyoAPIError.networkError(networkError)))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                result(.failure(KlaviyoAPIError.missingOrInvalidResponse(response)))
                return
            }
            guard 200 ..< 300 ~= response.statusCode else {
                result(.failure(KlaviyoAPIError.httpError(response.statusCode, data)))
                return
            }
            guard let data = data else {
                result(.failure(.invalidData))
                return
            }
            result(.success(data))
        }
    }
}

extension KlaviyoAPI.KlaviyoRequest {
    func urlRequest() throws -> URLRequest {
        let urlString = "\(environment.apiURL)/\(path)"
        guard let url = URL(string: urlString) else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("Invalid url string: \(urlString)")
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
                            
    var path: String {
        switch self.endpoint {
        case .createProfile:
            return "client/profiles"
        case .createEvent:
            return "client/events"
        case .legacyIdentify:
            return "api/identify"
        }
    }
    
    func encodeBody() throws -> Data {
        switch self.endpoint {
        case .createProfile(let payload):
            return try environment.encodeJSON(payload)
        case .createEvent(let payload):
            return try environment.encodeJSON(payload)
        case .legacyIdentify:
            return "deadbeef".data(using: .utf8)!
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
