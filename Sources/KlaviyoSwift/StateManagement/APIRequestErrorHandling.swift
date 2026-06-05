//
//  APIRequestErrorHandling.swift
//
//
//  Created by Noah Durell on 12/15/22.
//

import Foundation
import KlaviyoCore

func handleRequestError(
    request: KlaviyoRequest,
    error: KlaviyoAPIError,
    retryState: RetryState
) -> KlaviyoAction {
    switch error {
    case let .httpError(statuscode, data):
        let responseString = String(data: data, encoding: .utf8) ?? "[Unknown]"
        environment.logger.error("An http error occured status code: \(statuscode) data: \(responseString)")

        let invalidFields = parseError(data)
        if let invalidFields, !invalidFields.isEmpty {
            return .resetStateAndDequeue(request, invalidFields)
        } else {
            return .deQueueCompletedResults(request)
        }

    case let .networkError(error):
        environment.logger.error("A network error occurred: \(error)")
        switch retryState {
        case let .retry(count):
            let requestRetryCount = count + 1
            return .requestFailed(request, .retry(requestRetryCount))
        case let .retryWithBackoff(requestCount, _, _):
            return .requestFailed(request, .retry(requestCount + 1))
        }

    case let .internalError(data):
        environment.emitDeveloperWarning("An internal error occurred msg: \(data)")
        return .deQueueCompletedResults(request)

    case let .internalRequestError(error):
        environment.emitDeveloperWarning("An internal request error occurred msg: \(error)")
        return .deQueueCompletedResults(request)

    case let .unknownError(error):
        environment.emitDeveloperWarning("An unknown request error occured \(error)")
        return .deQueueCompletedResults(request)

    case .dataEncodingError:
        environment.emitDeveloperWarning("A data encoding error occurred during transmission.")
        return .deQueueCompletedResults(request)

    case .invalidData:
        environment.emitDeveloperWarning("Invalid data supplied for request. Skipping.")
        return .deQueueCompletedResults(request)

    case let .rateLimitError(backOff), let .serverError(_, backOff):
        if case let .serverError(statusCode, _) = error {
            environment.logger.error("A server error occurred with status code: \(statusCode)")
        }
        var requestRetryCount = 0
        var totalRetryCount = 0
        switch retryState {
        case let .retry(count):
            requestRetryCount = count + 1
            totalRetryCount = requestRetryCount

        case let .retryWithBackoff(requestCount, totalCount, _):
            requestRetryCount = requestCount + 1
            totalRetryCount = totalCount + 1
        }

        return .requestFailed(
            request, .retryWithBackoff(
                requestCount: requestRetryCount,
                totalRetryCount: totalRetryCount,
                currentBackoff: backOff
            )
        )

    case .missingOrInvalidResponse:
        runtimeWarn("Missing or invalid response from api.")
        return .deQueueCompletedResults(request)
    }
}
