//
//  SDKError.swift
//  klaviyo-swift-sdk
//

/// Errors surfaced by the Klaviyo SDK when the SDK is not properly initialized
/// or configured. Thrown by APIs that require initialization before use.
public enum SDKError: Error {
    /// The SDK has not been initialized. Call `KlaviyoSDK().initialize(with:)` first.
    case notInitialized

    /// The API key (Company ID) is nil or an empty string.
    case apiKeyNilOrEmpty
}
