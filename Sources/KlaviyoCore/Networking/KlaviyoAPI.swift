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
    environment.apiURL = url
}

public struct KlaviyoAPI {
    public init() {}

    // For internal testing use only
    public static var requestStarted: (KlaviyoRequest) -> Void = { _ in }
    public static var requestCompleted: (KlaviyoRequest, Data, Double) -> Void = { _, _, _ in }
    public static var requestFailed: (KlaviyoRequest, Error, Double) -> Void = { _, _, _ in }
    public static var requestRateLimited: (KlaviyoRequest, Int?) -> Void = { _, _ in }
    public static var requestHttpError: (KlaviyoRequest, Int, Double) -> Void = { _, _, _ in }

    public var send: (KlaviyoRequest, Int) async -> Result<Data, KlaviyoAPIError> = { request, attemptNumber in
        let start = environment.date()

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
            (data, response) = try await environment.networkSession().data(urlRequest)
        } catch {
            requestFailed(request, error, 0.0)
            return .failure(KlaviyoAPIError.networkError(error))
        }

        let end = environment.date()
        let duration = end.timeIntervalSince(start)

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.missingOrInvalidResponse(response))
        }

        if httpResponse.statusCode == 429, httpResponse.statusCode == 503 {
            let exponentialBackOff = Int(pow(2.0, Double(attemptNumber)))
            var nextBackoff: Int = exponentialBackOff
            if let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") {
                nextBackoff = Int(retryAfter) ?? exponentialBackOff
            }

            let jitter = environment.randomInt()
            let nextBackOffWithJitter = nextBackoff + jitter

            requestRateLimited(request, nextBackOffWithJitter)
            return .failure(KlaviyoAPIError.rateLimitError(nextBackOffWithJitter))
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            requestHttpError(request, httpResponse.statusCode, duration)
            return .failure(KlaviyoAPIError.httpError(httpResponse.statusCode, data))
        }

        requestCompleted(request, data, duration)

        return .success(data)
    }
}
