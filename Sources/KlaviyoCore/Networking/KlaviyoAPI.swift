//
//  KlaviyoAPI.swift
//
//
//  Created by Noah Durell on 11/8/22.
//

import AnyCodable
import Foundation

public struct KlaviyoAPI {
    public var send: (KlaviyoRequest, RequestAttemptInfo) async -> Result<Data, KlaviyoAPIError>

    public init(send: @escaping (KlaviyoRequest, RequestAttemptInfo) async -> Result<Data, KlaviyoAPIError> = { request, requestAttemptInfo in
        let start = environment.date()

        var urlRequest: URLRequest
        do {
            urlRequest = try request.urlRequest(attemptInfo: requestAttemptInfo)
        } catch {
            requestHandler(request, nil, .error(.requestFailed(error)))
            return .failure(.internalRequestError(error))
        }

        requestHandler(request, urlRequest, .started)

        var response: URLResponse
        var data: Data
        do {
            (data, response) = try await environment.networkSession().data(urlRequest)
        } catch {
            requestHandler(request, urlRequest, .error(.requestFailed(error)))
            return .failure(KlaviyoAPIError.networkError(error))
        }

        let end = environment.date()
        let duration = end.timeIntervalSince(start)

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.missingOrInvalidResponse(response))
        }

        // Consolidated retryable error handling (429 rate limit + all 5xx server errors).
        // The entire 5xx range (500–599) is treated as transient so we also retry CDN/edge
        // failures such as Cloudflare's 520–527 codes, which originate in front of the origin
        // servers and were the codes observed during the cannot-access-klaviyo-com incident.
        // 403 and other 4xx codes are intentionally excluded so the backend can shed load.
        if httpResponse.statusCode == 429 || (500...599).contains(httpResponse.statusCode) {
            let exponentialBackOff = Int(pow(2.0, Double(requestAttemptInfo.attemptNumber)))
            var nextBackoff: Int = exponentialBackOff
            // Check Retry-After header for any retryable error (expected for 429, future-proofing for 5xx)
            if let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") {
                nextBackoff = Int(retryAfter) ?? exponentialBackOff
            }
            let jitter = environment.randomInt()
            let nextBackOffWithJitter = nextBackoff + jitter

            if httpResponse.statusCode == 429 {
                requestHandler(request, urlRequest, .error(.rateLimited(retryAfter: nextBackOffWithJitter)))
                return .failure(KlaviyoAPIError.rateLimitError(backOff: nextBackOffWithJitter))
            } else {
                let status = httpResponse.statusCode
                let httpError = RequestStatus.error(.httpError(statusCode: status, duration: duration))
                requestHandler(request, urlRequest, httpError)
                return .failure(.serverError(statusCode: status, backOff: nextBackOffWithJitter))
            }
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            requestHandler(request, urlRequest, .error(.httpError(statusCode: httpResponse.statusCode, duration: duration)))
            return .failure(KlaviyoAPIError.httpError(httpResponse.statusCode, data))
        }

        requestHandler(request, urlRequest, .completed(data: data, duration: duration))

        return .success(data)
    }) {
        self.send = send
    }

    // For internal testing use only
    public static var requestHandler: (KlaviyoRequest, URLRequest?, RequestStatus) -> Void = { _, _, _ in }
}
