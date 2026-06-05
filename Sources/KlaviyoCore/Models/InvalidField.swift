//
//  InvalidField.swift
//
//  KlaviyoCore
//

import Foundation

/// An identity field that the Klaviyo API has rejected as invalid.
public enum InvalidField: Equatable {
    case email
    case phone

    /// Derives the invalid field from a Klaviyo API error `source.pointer` path.
    public static func getInvalidField(sourcePointer: String) -> InvalidField? {
        if sourcePointer.contains("/attributes/phone_number") { return .phone }
        if sourcePointer.contains("/attributes/email") { return .email }
        return nil
    }
}

// MARK: - Internal error response decoding

struct ErrorResponse: Codable {
    let errors: [ErrorDetail]
}

struct ErrorDetail: Codable {
    let id: String
    let status: Int
    let code: String
    let title: String
    let detail: String
    let source: ErrorSource
}

struct ErrorSource: Codable {
    let pointer: String
}

/// Parses a Klaviyo API error response body and returns the invalid fields, if any.
public func parseError(_ data: Data) -> [InvalidField]? {
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
