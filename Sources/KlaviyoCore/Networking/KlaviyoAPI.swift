//
//  KlaviyoAPI.swift
//
//
//  Created by Noah Durell on 11/8/22.
//

import AnyCodable
import Foundation

/// Named HTTP status codes and ranges referenced by the retry logic below.
///
/// This enum must be `public` because its members are referenced from the default
/// value of `KlaviyoAPI.init(send:)` — a `public init`. Swift requires any symbol
/// referenced from a public function's default argument to also be `public`, so a
/// `private`/`internal` enum would fail to compile on every toolchain.
public enum HTTPStatusCode {
    public static let rateLimited = 429
    public static let retryableServerErrorRange = 500...599
}

enum RetryBackoffConstants {
    /// Ceiling on the SDK's exponential backoff interval, in seconds (5 minutes).
    ///
    /// Bounds our own backoff so it can't grow unbounded across a long rate-limit storm. Aligns with
    /// comparable SDKs (Segment caps at 300s) per MAGE-500. A server-provided `Retry-After` may still
    /// exceed this ceiling — only the SDK-computed backoff is capped.
    static let maxBackoffSeconds = 300
}

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

        // Consolidated retryable error handling (429 rate limit + transient 5xx server errors).
        // The entire 5xx range (500–599) is treated as transient and retried — including CDN/edge
        // failures such as Cloudflare's 520–527 codes, which originate in front of the origin
        // servers and were the codes observed during the cannot-access-klaviyo-com incident.
        // We deliberately retry even 501 (Not Implemented) and 505 (HTTP Version Not Supported):
        // for the SDK's fixed request shapes a genuine origin 501/505 is effectively unreachable,
        // so any 5xx we actually see is edge/CDN noise during an incident — exactly what we want
        // to retry (incident data-retention outweighs the negligible cost of a wasted retry).
        // 403 and other 4xx codes are intentionally excluded so the backend can shed load.
        let code = httpResponse.statusCode
        let isRetryableServerError = HTTPStatusCode.retryableServerErrorRange.contains(code)
        if code == HTTPStatusCode.rateLimited || isRetryableServerError {
            // Cap our exponential backoff at the max retry interval so it can't grow unbounded
            // across a long rate-limit storm. A server-provided Retry-After may still exceed this.
            let exponentialBackOff = min(
                Int(pow(2.0, Double(requestAttemptInfo.attemptNumber))),
                RetryBackoffConstants.maxBackoffSeconds
            )
            // Wait the GREATER of the server-provided Retry-After and our exponential backoff
            // (Retry-After expected for 429, future-proofing for 5xx). Taking the greater of the two
            // keeps a request deep in a rate-limit storm backing off rather than retrying too soon
            // just because the server's rate-limit window reset to a short Retry-After.
            var nextBackoff: Int = exponentialBackOff
            if let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After"),
               let retryAfterSeconds = Int(retryAfter) {
                nextBackoff = max(exponentialBackOff, retryAfterSeconds)
            }
            let jitter = environment.randomInt()
            let nextBackOffWithJitter = nextBackoff + jitter

            if code == HTTPStatusCode.rateLimited {
                requestHandler(request, urlRequest, .error(.rateLimited(retryAfter: nextBackOffWithJitter)))
                return .failure(KlaviyoAPIError.rateLimitError(backOff: nextBackOffWithJitter))
            } else {
                let httpError = RequestStatus.error(.httpError(statusCode: code, duration: duration))
                requestHandler(request, urlRequest, httpError)
                return .failure(.serverError(statusCode: code, backOff: nextBackOffWithJitter))
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
