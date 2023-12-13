//
//  APIRequestErrorHandling.swift
//
//
//  Created by Noah Durell on 12/15/22.
//

import Foundation

struct ErrorHandlingConstants {
    static let maxRetries = 50
    static let maxBackoff = 60 * 3 // 3 minutes
}

enum InvalidField: Equatable {
    case email
    case phone

    /// gets the invalid field based on the source.pointer from klaviyo API.
    /// this assumes that source.pointer will not change
    /// Client APIs to have better error codes in the future at which point we should use that instead of source.pointer
    /// - Parameter sourcePointer: pointers to the source of the error
    /// - Returns: the field that is invalid else `nil`
    static func getInvalidField(sourcePointer: String) -> InvalidField? {
        if sourcePointer == "/data/attributes/phone_number" {
            return .phone
        }
        if sourcePointer == "/data/attributes/email" {
            return .email
        }

        return nil
    }
}

private func getDelaySeconds(for count: Int) -> Int {
    let delay = Int(pow(2.0, Double(count)))
    let jitter = environment.randomInt()
    return min(delay + jitter, ErrorHandlingConstants.maxBackoff)
}

private func parseError(_ data: Data) -> [InvalidField]? {
    var invalidFields: [InvalidField]?
    do {
        let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)

        invalidFields = errorResponse.errors.compactMap { error in
            InvalidField.getInvalidField(sourcePointer: error.source.pointer)
        }
    } catch {
        environment.logger.error("error when decoding error data")
    }

    return invalidFields
}

func handleRequestError(
    request: KlaviyoAPI.KlaviyoRequest,
    error: KlaviyoAPI.KlaviyoAPIError,
    retryInfo: RetryInfo) -> KlaviyoAction {
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
        switch retryInfo {
        case let .retry(count):
            let requestRetryCount = count + 1
            return .requestFailed(request, .retry(requestRetryCount))
        case let .retryWithBackoff(requestCount, _, _):
            return .requestFailed(request, .retry(requestCount + 1))
        }

    case let .internalError(data):
        runtimeWarn("An internal error occurred msg: \(data)")
        return .deQueueCompletedResults(request)

    case let .internalRequestError(error):
        runtimeWarn("An internal request error occurred msg: \(error)")
        return .deQueueCompletedResults(request)

    case let .unknownError(error):
        runtimeWarn("An unknown request error occured \(error)")
        return .deQueueCompletedResults(request)

    case .dataEncodingError:
        runtimeWarn("A data encoding error occurred during transmission.")
        return .deQueueCompletedResults(request)

    case .invalidData:
        runtimeWarn("Invalid data supplied for request. Skipping.")
        return .deQueueCompletedResults(request)

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
        return .requestFailed(
            request, .retryWithBackoff(
                requestCount: requestRetryCount,
                totalRetryCount: totalRetryCount,
                currentBackoff: nextBackoff))

    case .missingOrInvalidResponse:
        runtimeWarn("Missing or invalid response from api.")
        return .deQueueCompletedResults(request)
    }
}
