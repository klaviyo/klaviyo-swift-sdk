//
// KlaviyoAPIError.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Foundation

public enum KlaviyoAPIError: Error {
    case httpError(Int, Data)
    case rateLimitError(backOff: Int)
    case serverError(statusCode: Int, backOff: Int)
    case missingOrInvalidResponse(URLResponse?)
    case networkError(Error)
    case internalError(String)
    case internalRequestError(Error)
    case unknownError(Error)
    case dataEncodingError(KlaviyoRequest)
    case invalidData
}
