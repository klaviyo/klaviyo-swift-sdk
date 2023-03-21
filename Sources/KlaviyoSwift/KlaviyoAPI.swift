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
        case rateLimitError
        case missingOrInvalidResponse(URLResponse?)
        case networkError(Error)
        case internalError(String)
        case internalRequestError(Error)
        case unknownError(Error)
        case dataEncodingError(KlaviyoRequest)
        case invalidData
    }

    // For internal testing use only
    static var requestStarted: (KlaviyoRequest) -> Void = { _ in }
    static var requestCompleted: (KlaviyoRequest, Data, Double) -> Void = { _, _, _ in }
    static var requestFailed: (KlaviyoRequest, Error, Double) -> Void = { _, _, _ in }
    static var requestRateLimited: (KlaviyoRequest) -> Void = { _ in }
    static var requestHttpError: (KlaviyoRequest, Int, Double) -> Void = { _, _, _ in }

    var send: (KlaviyoRequest) async -> Result<Data, KlaviyoAPIError> = { request in
        let start = Date()
        var urlRequest: URLRequest
        do {
            urlRequest = try request.urlRequest()
        } catch {
            requestFailed(request, error, 0.0)
            return .failure(.internalRequestError(error))
        }

        requestStarted(request)
        var response: URLResponse
        var data: Data
        do {
            (data, response) = try await environment.analytics.networkSession().data(urlRequest)
        } catch {
            requestFailed(request, error, 0.0)
            return .failure(KlaviyoAPIError.networkError(error))
        }
        let end = Date()
        let duration = end.timeIntervalSince(start)
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.missingOrInvalidResponse(response))
        }
        if httpResponse.statusCode == 429 {
            requestRateLimited(request)
            return .failure(KlaviyoAPIError.rateLimitError)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            requestHttpError(request, httpResponse.statusCode, duration)
            return .failure(KlaviyoAPIError.httpError(httpResponse.statusCode, data))
        }
        requestCompleted(request, data, duration)
        return .success(data)
    }
}

extension KlaviyoAPI.KlaviyoRequest {
    func urlRequest() throws -> URLRequest {
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

        return request
    }

    var url: URL? {
        switch endpoint {
        case .createProfile, .createEvent:
            return URL(string: "\(environment.analytics.apiURL)/\(path)/?company_id=\(apiKey)")
        case .storePushToken:
            return URL(string: "\(environment.analytics.apiURL)/\(path)")
        }
    }

    var path: String {
        switch endpoint {
        case .createProfile:
            return "client/profiles"
        case .createEvent:
            return "client/events"
        case .storePushToken:
            return "api/identify"
        }
    }

    func encodeBody() throws -> Data {
        switch endpoint {
        case let .createProfile(payload):
            return try environment.analytics.encodeJSON(AnyEncodable(payload))
        case let .createEvent(payload):
            return try environment.analytics.encodeJSON(AnyEncodable(payload))
        case let .storePushToken(payload):
            return try environment.analytics.encodeJSON(AnyEncodable(payload))
        }
    }
}
