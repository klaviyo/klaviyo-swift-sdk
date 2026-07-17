//
// Error.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Foundation

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
