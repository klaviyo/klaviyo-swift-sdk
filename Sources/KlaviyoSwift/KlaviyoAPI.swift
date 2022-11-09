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
          struct CreateProfilePayload: Codable {
              struct ProfileData: Codable {
                  struct ProfileAttributes: Codable {
                      struct ProfileLocation: Codable {
                          public let address1: String?
                          public let address2: String?
                          public let city: String?
                          public let country: String?
                          public let latitude: Double?
                          public let longitude: Double?
                          public let region: String?
                          public let zip: String?
                          public let timeZone: String?
                          enum CodingKeys: String, CodingKey {
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
                      let email: String?
                      let phoneNumber: String?
                      let externalId: String?
                      let firstName: String?
                      let lastName: String?
                      let organization: String?
                      let title: String?
                      let image: String?
                      let location: ProfileLocation?
                      let properties: [String: Codable]?
                      enum CodingKeys: String, CodingKey {
                          case email
                          case phoneNumber
                          case externalId
                          case firstName
                          case lastName
                          case organization
                          case title
                          case image
                          case location
                          case properties
                          
                      }
                  }
                  let attributes: ProfileAttributes
                  enum CodingKeys: String, CodingKey {
                      case attributes
                  }
              }
              let data: ProfileData
              
          }
          struct CreateEventPayload: Encodable {
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
                guard let body = self.body?.data(using: .utf8) else {
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
    
    var body: String? {
        switch self.endpoint {
        case .createProfile(_):
            return "DEADBEEF"
        case .createEvent(_):
            return "DEADBEEF"
        }
    }
}
