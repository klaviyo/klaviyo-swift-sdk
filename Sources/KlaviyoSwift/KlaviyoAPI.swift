//
//  KlaviyoAPI.swift
//
//
//  Created by Noah Durell on 11/8/22.
//

import AnyCodable
import Foundation

@_spi(KlaviyoPrivate)
public func setKlaviyoAPIURL(url: String) {
    environment.analytics.apiURL = url
}

struct KlaviyoAPI {
    struct KlaviyoRequest: Equatable, Codable {
        public let apiKey: String
        public let endpoint: KlaviyoEndpoint
        public var uuid = environment.analytics.uuid().uuidString
    }

    enum KlaviyoAPIError: Error {
        case httpError(Int, Data)
        case rateLimitError(Int?)
        case missingOrInvalidResponse(URLResponse?)
        case networkError(Error)
        case internalError(String)
        case internalRequestError(Error)
        case unknownError(Error)
        case dataEncodingError(KlaviyoRequest)
        case invalidData
    }

    // For internal testing use only
    static var requestHandler: (KlaviyoRequest, URLRequest?, RequestStatus) -> Void = { _, _, _ in }
    
    var send: (KlaviyoRequest, Int) async -> Result<Data, KlaviyoAPIError> = { request, attemptNumber in
        let start = Date()

        var urlRequest: URLRequest
        do {
            urlRequest = try request.urlRequest(attemptNumber)
        } catch {
            requestHandler(request, nil, .error(.requestFailed(error)))
            return .failure(.internalRequestError(error))
        }

        requestHandler(request, urlRequest, .started)

        var response: URLResponse
        var data: Data
        do {
            (data, response) = try await environment.analytics.networkSession().data(urlRequest)
        } catch {
            requestHandler(request, urlRequest, .error(.requestFailed(error)))
            return .failure(KlaviyoAPIError.networkError(error))
        }

        let end = Date()
        let duration = end.timeIntervalSince(start)

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.missingOrInvalidResponse(response))
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "0") ?? 0
            requestHandler(request, urlRequest, .error(.rateLimited(retryAfter: retryAfter)))
            return .failure(KlaviyoAPIError.rateLimitError(retryAfter))
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            requestHandler(request, urlRequest, .error(.httpError(statusCode: httpResponse.statusCode, duration: duration)))
            return .failure(KlaviyoAPIError.httpError(httpResponse.statusCode, data))
        }

        requestHandler(request, urlRequest, .completed(data: data, duration: duration))

        return .success(data)
    }
}

extension KlaviyoAPI.KlaviyoRequest {
    func urlRequest(_ attemptNumber: Int = StateManagementConstants.initialAttempt) throws -> URLRequest {
        guard let url = url else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("Invalid url string. API URL: \(environment.analytics.apiURL)")
        }
        var request = URLRequest(url: url)
        // We only support post right now
        guard let body = try? encodeBody() else {
            throw KlaviyoAPI.KlaviyoAPIError.dataEncodingError(self)
        }
        request.httpBody = body
        request.httpMethod = "POST"
        request.setValue("\(attemptNumber)/50", forHTTPHeaderField: "X-Klaviyo-Attempt-Count")

        return request
    }

    var url: URL? {
        switch endpoint {
        case .createProfile, .createEvent, .registerPushToken, .unregisterPushToken:
            if !environment.analytics.apiURL.isEmpty {
                return URL(string: "\(environment.analytics.apiURL)/\(path)/?company_id=\(apiKey)")
            }
            return nil
        }
    }

    var path: String {
        switch endpoint {
        case .createProfile:
            return "client/profiles"

        case .createEvent:
            return "client/events"

        case .registerPushToken:
            return "client/push-tokens"

        case .unregisterPushToken:
            return "client/push-token-unregister"
        }
    }

    func encodeBody() throws -> Data {
        switch endpoint {
        case let .createProfile(payload):
            return try environment.analytics.encodeJSON(AnyEncodable(payload))

        case var .createEvent(payload):
            payload.appendMetadataToProperties()
            return try environment.analytics.encodeJSON(AnyEncodable(payload))

        case let .registerPushToken(payload):
            return try environment.analytics.encodeJSON(AnyEncodable(payload))

        case let .unregisterPushToken(payload):
            return try environment.analytics.encodeJSON(AnyEncodable(payload))
        }
    }
}
