//
//  RequestErrorHandling.swift
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

func handleRequestErorr(request: KlaviyoAPI.KlaviyoRequest, error: KlaviyoAPI.KlaviyoAPIError, retryInfo: RetryInfo) -> KlaviyoAction {
    switch error {
    case let .httpError(statuscode, data):
        runtimeWarn("An http error occured status code: \(statuscode) data: \(data)")
        return .dequeCompletedResults(request)
    case .networkError(_):
        runtimeWarn("A network error occurred: \(error)")
        return KlaviyoAction.cancelInFlightRequests
    case .internalError(let data):
        runtimeWarn("An internal error occurred msg: \(data)")
        return .dequeCompletedResults(request)
    case .internalRequestError(let error):
        runtimeWarn("An internal request error occurred msg: \(error)")
        return .dequeCompletedResults(request)
    case .unknownError(let error):
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
        switch(retryInfo) {
        case .retry(let count):
            requestRetryCount = count + 1
            totalRetryCount = requestRetryCount
        case .retryWithBackoff(let requestCount, let totalCount, _):
            requestRetryCount = requestCount + 1
            totalRetryCount = totalCount + 1
            nextBackoff = getDelaySeconds(for: totalRetryCount)
        }
        return .requestFailed(request, .retryWithBackoff(requestRetryCount, totalRetryCount, nextBackoff))
    case .missingOrInvalidResponse:
        runtimeWarn("Missing or invalid response from api.")
        return .dequeCompletedResults(request)
    }
}
