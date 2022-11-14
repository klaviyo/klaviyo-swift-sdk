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
              struct Profile: Encodable {
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
                  let attributes: Attributes
                  init(profile: Klaviyo.Profile, anonymousId: String) {
                      self.attributes = Attributes(
                        attributes: profile.attributes,
                        anonymousId: anonymousId)
                  }
                  
                  enum CodingKeys: CodingKey {
                      case attributes
                  }
              }
              let data: Profile
              let type = "profile"
              enum CodingKeys: String, CodingKey {
                  case data
                  case type
              }
          }
          struct CreateEventPayload: Encodable {
              let data: Klaviyo.Event
              let type = "events"
              enum CodingKeys: CodingKey {
                  case data
                  case type
              }
          }
          case createProfile(CreateProfilePayload)
          case createEvent(CreateEventPayload)
      }
      let method = HTTPMethod.post
      let apiKey: String
      let endpoint: KlaviyoEndpoint
    }
    enum HTTPMethod {
        case post
        case get
    }
    enum KlaviyoAPIError: Error {
        case httpError(Int)
        case rateLimitError
        case missingOrInvalidResponse(URLResponse?)
        case networkError(Error)
        case internalError(String)
        case unknownError(Error)
        case dataEncodingError(KlaviyoRequest)
        case invalidData
    }
    var post: (KlaviyoRequest, @escaping (Result<Data, KlaviyoAPIError>) -> Void) -> Void = { request, result in
        var urlRequest: URLRequest
        do {
            urlRequest = try request.urlRequest()
        } catch {
            result(.failure(.unknownError(error)))
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
                result(.failure(KlaviyoAPIError.httpError(response.statusCode)))
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
        let urlString = "\(environment.apiURL)/client/\(path)"
        guard let url = URL(string: urlString) else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("Invalid url string: \(urlString)")
        }
        var request = URLRequest(url: url)
        switch self.method {
            case  .post:
                guard let body = try? self.encodeBody() else {
                    throw KlaviyoAPI.KlaviyoAPIError.dataEncodingError(self)
                }
                request.httpBody = body
            case .get:
                throw KlaviyoAPI.KlaviyoAPIError.internalError("Invalid http method")
        }
        
        return request
        
    }
                            
    var path: String {
        switch self.endpoint {
        case .createProfile:
            return "profiles"
        case .createEvent:
            return "events"
        }
    }
    
    func encodeBody() throws -> Data {
        switch self.endpoint {
        case .createProfile(let payload):
            return try environment.encodeJSON(payload)
        case .createEvent(let payload):
            return try environment.encodeJSON(payload)
        }
    }
}

extension Klaviyo.Profile.Attributes.Location: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address1, forKey: .address1)
        try container.encode(address2, forKey: .address2)
        try container.encode(city, forKey: .city)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(region, forKey: .region)
        try container.encode(zip, forKey: .zip)
        try container.encode(timeZone, forKey: .timeZone)
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
        case timeZone
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
