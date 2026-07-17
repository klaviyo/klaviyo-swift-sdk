//
// SDKError.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

package enum SDKError: Error {
    /// The SDK has not been initialized
    case notInitialized

    /// API Key (aka Company ID) is nil or an emtpy string
    case apiKeyNilOrEmpty
}
