//
//  KlaviyoAPI.swift
//
//
//  Created by Noah Durell on 11/8/22.
//

import Foundation
import KlaviyoSDKDependencies

public struct KlaviyoAPI: Sendable {
    public var send: @Sendable (NetworkSession, KlaviyoRequest, Int) async -> Result<Data, KlaviyoAPIError>

    public init(send: @Sendable @escaping (NetworkSession, KlaviyoRequest, Int) async -> Result<Data, KlaviyoAPIError> = { session, request, attemptNumber in
        let start = environment.date()

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
            (data, response) = try await session.data(urlRequest)
        } catch {
            requestHandler(request, urlRequest, .error(.requestFailed(error)))
            return .failure(KlaviyoAPIError.networkError(error))
        }

        let end = environment.date()
        let duration = end.timeIntervalSince(start)

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.missingOrInvalidResponse(response))
        }

        if httpResponse.statusCode == 429 || httpResponse.statusCode == 503 {
            let exponentialBackOff = Int(pow(2.0, Double(attemptNumber)))
            var nextBackoff: Int = exponentialBackOff
            if let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") {
                nextBackoff = Int(retryAfter) ?? exponentialBackOff
            }

            let jitter = environment.randomInt()
            let nextBackOffWithJitter = nextBackoff + jitter

            requestHandler(request, urlRequest, .error(.rateLimited(retryAfter: nextBackOffWithJitter)))
            return .failure(KlaviyoAPIError.rateLimitError(backOff: nextBackOffWithJitter))
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            requestHandler(request, urlRequest, .error(.httpError(statusCode: httpResponse.statusCode, duration: duration, data: data)))
            return .failure(KlaviyoAPIError.httpError(httpResponse.statusCode, data))
        }

        requestHandler(request, urlRequest, .completed(data: data, duration: duration))

        return .success(data)
    }) {
        self.send = send
    }

    // For internal testing use only
    #if swift(>=5.10)
    public nonisolated(unsafe) static var requestHandler: (KlaviyoRequest, URLRequest?, RequestStatus) -> Void = { _, _, _ in }
    #else
    public static var requestHandler: (KlaviyoRequest, URLRequest?, RequestStatus) -> Void = { _, _, _ in }
    #endif
}
