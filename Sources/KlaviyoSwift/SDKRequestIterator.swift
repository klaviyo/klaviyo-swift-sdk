//
//  File.swift
//
//
//  Created by Noah Durell on 2/13/23.
//

import AnyCodable
import Foundation

@_spi(KlaviyoPrivate)
public struct SDKRequest: Identifiable, Equatable {
    @_spi(KlaviyoPrivate)
    public enum RequestType: Equatable {
        public struct EventInfo: Equatable {
            public let eventName: String

            @_spi(KlaviyoPrivate)
            public init(eventName: String) {
                self.eventName = eventName
            }
        }

        @_spi(KlaviyoPrivate)
        public struct ProfileInfo: Equatable {
            public var email: String?
            public var phoneNumber: String?
            public var externalId: String?
            public var anonymousId: String

            @_spi(KlaviyoPrivate)
            public init(email: String? = nil,
                        phoneNumber: String? = nil,
                        externalId: String? = nil,
                        anonymousId: String,
                        customerProperties _: String? = nil) {
                self.email = email
                self.phoneNumber = phoneNumber
                self.externalId = externalId
                self.anonymousId = anonymousId
            }
        }

        case createEvent(EventInfo, ProfileInfo)
        case createProfile(ProfileInfo)
        case saveToken(token: String, info: ProfileInfo)
        case unregisterToken(token: String, info: ProfileInfo)

        static func fromEndpoint(request: KlaviyoAPI.KlaviyoRequest) -> RequestType {
            switch request.endpoint {
            case let .createProfile(payload):

                return .createProfile(ProfileInfo(
                    email: payload.data.attributes.email,
                    phoneNumber: payload.data.attributes.phoneNumber,
                    externalId: payload.data.attributes.externalId,
                    anonymousId: payload.data.attributes.anonymousId))
            case let .createEvent(payload):
                return .createEvent(
                    EventInfo(eventName: payload.data.attributes.metric.data.attributes.name),
                    ProfileInfo(email: payload.data.attributes.profile.data.attributes.email,
                                phoneNumber: payload.data.attributes.profile.data.attributes.phoneNumber,
                                externalId: payload.data.attributes.profile.data.attributes.externalId,
                                anonymousId: payload.data.attributes.profile.data.attributes.anonymousId))
            case let .registerPushToken(payload):
                return .saveToken(token: payload.data.attributes.token, info:
                    ProfileInfo(email: payload.data.attributes.profile.data.attributes.email,
                                phoneNumber: payload.data.attributes.profile.data.attributes.phoneNumber,
                                externalId: payload.data.attributes.profile.data.attributes.externalId,
                                anonymousId: payload.data.attributes.profile.data.attributes.anonymousId))
            case let .unregisterPushToken(payload):
                return .unregisterToken(token: payload.data.attributes.token, info:
                    ProfileInfo(email: payload.data.attributes.profile.data.attributes.email,
                                phoneNumber: payload.data.attributes.profile.data.attributes.phoneNumber,
                                externalId: payload.data.attributes.profile.data.attributes.externalId,
                                anonymousId: payload.data.attributes.profile.data.attributes.anonymousId))
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

    static func fromAPIRequest(request: KlaviyoAPI.KlaviyoRequest, urlRequest: URLRequest?, response: SDKRequest.Response) -> SDKRequest {
        let type = RequestType.fromEndpoint(request: request)
        let method = urlRequest?.httpMethod ?? "Unknown"
        let url = urlRequest?.url?.description ?? "Unknown"
        return SDKRequest(id: request.uuid,
                          type: type,
                          url: url,
                          method: method,
                          payloadSize: 1.0,
                          headers: urlRequest?.allHTTPHeaderFields ?? [:],
                          response: response,
                          requestBody: urlRequest?.httpBody ?? Data())
    }

    public var id: String
    public let requestBody: Data
    public let type: RequestType
    public let url: String
    public let method: String
    public let payloadSize: Double
    public let headers: [String: String]
    public let response: Response

    @_spi(KlaviyoPrivate)
    public init(id: String,
                type: RequestType,
                url: String, method:
                String, payloadSize:
                Double, headers: [String: String],
                response: Response,
                requestBody: Data) {
        self.id = id
        self.type = type
        self.url = url
        self.method = method
        self.payloadSize = payloadSize
        self.headers = headers
        self.response = response
        self.requestBody = requestBody
    }
}

@_spi(KlaviyoPrivate)
public enum RequestStatus {
    public enum RequestError: Error {
        case requestFailed(Error)
        /// The server responded with a 429 HTTP status code, indicating that the client is being rate-limited.
        /// - Parameter retryAfter: The amount of time, in seconds, that the client should wait before making another request.
        case rateLimited(retryAfter: Int)
        /// - Parameter duration: The elapsed time, in seconds, between the API call and the server’s response.
        case httpError(statusCode: Int, duration: TimeInterval)
    }
    
    case started
    /// - Parameter duration: The elapsed time, in seconds, between the API call and the server’s response.
    case completed(data: Data, duration: TimeInterval)
    case error(RequestError)
}

@_spi(KlaviyoPrivate)
public func requestIterator() -> AsyncStream<SDKRequest> {
    AsyncStream<SDKRequest> { continuation in
        continuation.onTermination = { _ in
            KlaviyoAPI.requestStarted = { _, _ in }
            KlaviyoAPI.requestFailed = { _, _, _, _ in }
            KlaviyoAPI.requestCompleted = { _, _, _, _ in }
            KlaviyoAPI.requestHttpError = { _, _, _, _ in }
            KlaviyoAPI.requestRateLimited = { _, _, _ in }
        }
        KlaviyoAPI.requestStarted = { request, urlRequest in
            continuation.yield(SDKRequest.fromAPIRequest(request: request, urlRequest: urlRequest, response: .inProgress))
        }
        KlaviyoAPI.requestCompleted = { request, urlRequest, data, duration in
            let dataDescription = String(data: data, encoding: .utf8) ?? "Invalid Data"
            continuation.yield(SDKRequest.fromAPIRequest(request: request, urlRequest: urlRequest, response: .success(dataDescription, duration)))
        }
        KlaviyoAPI.requestFailed = { request, urlRequest, error, duration in
            continuation.yield(SDKRequest.fromAPIRequest(request: request, urlRequest: urlRequest, response: .reqeustError(error.localizedDescription, duration)))
        }
        KlaviyoAPI.requestHttpError = { request, urlRequest, statusCode, duration in
            continuation.yield(SDKRequest.fromAPIRequest(request: request, urlRequest: urlRequest, response: .httpError(statusCode, duration)))
        }
        KlaviyoAPI.requestRateLimited = { request, urlRequest, retryAfter in
            continuation.yield(SDKRequest.fromAPIRequest(request: request, urlRequest: urlRequest, response: .reqeustError("Rate Limited", Double(retryAfter ?? 0))))
        }
    }
}
