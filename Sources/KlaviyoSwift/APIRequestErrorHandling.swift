//
//  APIRequestErrorHandling.swift
//
//
//  Created by Noah Durell on 12/15/22.
//

import Foundation

let MAX_RETRIES = 50
let MAX_BACKOFF = 60 * 3 // 3 minutes

private func getDelaySeconds(for count: Int) -> Int {
    let delay = Int(pow(2.0, Double(count)))
    let jitter = environment.randomInt()
    return min(delay + jitter, MAX_BACKOFF)
}

func handleRequestError(request: KlaviyoAPI.KlaviyoRequest, error: KlaviyoAPI.KlaviyoAPIError, retryInfo: RetryInfo) -> KlaviyoAction {
    switch error {
    case let .httpError(statuscode, data):
        environment.logger.error("An http error occured status code: \(statuscode) data: \(data)")
        return .dequeCompletedResults(request)
    case let .networkError(error):
        environment.logger.error("A network error occurred: \(error)")
        switch retryInfo {
        case let .retry(count):
            let requestRetryCount = count + 1
            return KlaviyoAction.requestFailed(request, .retry(requestRetryCount))
        case let .retryWithBackoff(requestCount, _, _):
            return .requestFailed(request, .retry(requestCount + 1))
        }
    case let .internalError(data):
        runtimeWarn("An internal error occurred msg: \(data)")
        return .dequeCompletedResults(request)
    case let .internalRequestError(error):
        runtimeWarn("An internal request error occurred msg: \(error)")
        return .dequeCompletedResults(request)
    case let .unknownError(error):
        runtimeWarn("An unknown request error occured \(error)")
        return .dequeCompletedResults(request)
    case .dataEncodingError:
        runtimeWarn("A data encoding error occurred during transmission.")
        return .dequeCompletedResults(request)
    case .invalidData:
        runtimeWarn("Invalid data supplied for request. Skipping.")
        return .dequeCompletedResults(request)
    case .rateLimitError:
        var requestRetryCount = 0
        var totalRetryCount = 0
        var nextBackoff = 0
        switch retryInfo {
        case let .retry(count):
            requestRetryCount = count + 1
            totalRetryCount = requestRetryCount
        case let .retryWithBackoff(requestCount, totalCount, _):
            requestRetryCount = requestCount + 1
            totalRetryCount = totalCount + 1
            nextBackoff = getDelaySeconds(for: totalRetryCount)
        }
        return .requestFailed(request, .retryWithBackoff(requestCount: requestRetryCount, totalRetryCount: totalRetryCount, currentBackoff: nextBackoff))
    case .missingOrInvalidResponse:
        runtimeWarn("Missing or invalid response from api.")
        return .dequeCompletedResults(request)
    }
}
