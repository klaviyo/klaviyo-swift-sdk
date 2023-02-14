//
//  File.swift
//  
//
//  Created by Noah Durell on 2/13/23.
//

import Foundation
import AnyCodable

extension AnyCodable {
    var jsonRepresentation: String {
        let anyEncodable = AnyEncodable(self)
        let encodedData = try? environment.analytics.encodeJSON(anyEncodable)
        guard let encodedData = encodedData else {
            return "Unable to decode data."
        }
        return String(data: encodedData, encoding: .utf8) ?? "Unable to decode data."
    }
}

@_spi(KlaviyoPrivate)
public struct SDKRequest: Identifiable, Equatable {
    public var id: String
    
    @_spi(KlaviyoPrivate)
    public enum RequestType: Equatable {
        public struct EventInfo: Equatable {
            public let eventName: String
            public let eventPayload: String
        }
        public struct ProfileInfo: Equatable {
            public var email: String? = nil
            public var phoneNumber: String? = nil
            public var externalId: String? = nil
            public var anonymousId: String
            public var customerProperties: String? = nil
        }
        case createEvent(EventInfo, ProfileInfo)
        case createProfile(ProfileInfo)
        case saveToken(token: String, info: ProfileInfo)
        
        
        static func fromEndpoint(request: KlaviyoAPI.KlaviyoRequest) -> RequestType {
            switch request.endpoint {
                
            case .createProfile(let payload):

                return .createProfile(ProfileInfo(
                    email: payload.data.attributes.email,
                    phoneNumber: payload.data.attributes.phoneNumber,
                    externalId: payload.data.attributes.externalId,
                    anonymousId: payload.data.attributes.anonymousId,
                    customerProperties: payload.data.attributes.properties.jsonRepresentation
                ))
            case .createEvent(let payload):
                let profile = payload.data.attributes.profile.value as? [String: Any] ?? [:]
                return .createEvent(
                    EventInfo(eventName: payload.data.attributes.metric.name,
                              eventPayload: payload.data.attributes.properties.jsonRepresentation),
                    ProfileInfo(anonymousId:  profile["$anonymous"] as? String ?? "Unknown", customerProperties: payload.data.attributes.profile.jsonRepresentation))
            case .storePushToken(let payload):
                return .saveToken(token: payload.token, info:
                                    ProfileInfo(email: payload.properties.email,
                                                phoneNumber: payload.properties.phoneNumber,
                                                externalId: payload.properties.externalId,
                                                anonymousId: payload.properties.anonymousId ?? "Unknown"))
            }
        }

    }
    @_spi(KlaviyoPrivate)
    public enum Response: Equatable {
        case inProgress
        case success(String, Double)
        case httpError(Int, Double)
        case reqeustError(String, Double)
    }
    static func fromAPIRequest(request: KlaviyoAPI.KlaviyoRequest, response: SDKRequest.Response) -> SDKRequest {
        let type = RequestType.fromEndpoint(request: request)
        let urlRequest = try? request.urlRequest()
        let method = urlRequest?.httpMethod ?? "Unknown"
        let url = urlRequest?.url?.description ?? "Unknown"
        return SDKRequest(id: request.uuid,
                          type: type,
                          url: url,
                          method: method,
                          payloadSize: 1.0,
                          headers: urlRequest?.allHTTPHeaderFields ?? [:],
                          response: response)
    }
    
    public let type: RequestType
    public let url: String
    public let method: String
    public let payloadSize: Double
    public let headers: [String: String]
    public let response: Response
}

@_spi(KlaviyoPrivate)
public func requestIterator() -> AsyncStream<SDKRequest> {
    return AsyncStream<SDKRequest> { continuation in
        KlaviyoAPI.requestStarted = { request in
            continuation.yield(SDKRequest.fromAPIRequest(request: request, response: .inProgress))
        }
        KlaviyoAPI.requestCompleted = { request, data, duration in
            let dataDescription = String(data: data, encoding: .utf8) ?? "Invalid Data"
            continuation.yield(SDKRequest.fromAPIRequest(request: request, response: .success(dataDescription, duration)))
   
        }
        KlaviyoAPI.requestFailed = { request, error, duration in
            continuation.yield(SDKRequest.fromAPIRequest(request: request, response: .reqeustError(error.localizedDescription, duration)))
        }
        KlaviyoAPI.requestHttpError = { request, statusCode, duration in
            continuation.yield(SDKRequest.fromAPIRequest(request: request, response: .httpError(statusCode, duration)))
        }
      Task {
          while(true) {
              guard !Task.isCancelled else {
                  continuation.finish()
                  return
              }
              try? await Task.sleep(nanoseconds: 100_000)
          }
      }
    }
}
