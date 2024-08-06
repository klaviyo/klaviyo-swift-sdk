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
    analytics.apiURL = url
}

public struct KlaviyoAPI {
    public init() {}

    public enum KlaviyoAPIError: Error {
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
    public static var requestStarted: (KlaviyoRequest) -> Void = { _ in }
    public static var requestCompleted: (KlaviyoRequest, Data, Double) -> Void = { _, _, _ in }
    public static var requestFailed: (KlaviyoRequest, Error, Double) -> Void = { _, _, _ in }
    public static var requestRateLimited: (KlaviyoRequest, Int?) -> Void = { _, _ in }
    public static var requestHttpError: (KlaviyoRequest, Int, Double) -> Void = { _, _, _ in }

    public var send: (KlaviyoRequest, Int) async -> Result<Data, KlaviyoAPIError> = { request, attemptNumber in
        let start = Date()

        var urlRequest: URLRequest
        do {
            urlRequest = try request.urlRequest(attemptNumber)
        } catch {
            requestFailed(request, error, 0.0)
            return .failure(.internalRequestError(error))
        }

        requestStarted(request)

        var response: URLResponse
        var data: Data
        do {
            (data, response) = try await analytics.networkSession().data(urlRequest)
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
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "0")
            requestRateLimited(request, retryAfter)
            return .failure(KlaviyoAPIError.rateLimitError(retryAfter))
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            requestHttpError(request, httpResponse.statusCode, duration)
            return .failure(KlaviyoAPIError.httpError(httpResponse.statusCode, data))
        }

        requestCompleted(request, data, duration)

        return .success(data)
    }
}
