//
//  Klaviyo+AuthToken.swift
//  KlaviyoSwift
//
//  Created by Andrew Balmer on 2026-05-14.
//

import KlaviyoCore

/// Re-exports ``KlaviyoCore/AuthTokenProvider`` so host code that imports only
/// `KlaviyoSwift` can reference the closure type without a second import.
public typealias AuthTokenProvider = KlaviyoCore.AuthTokenProvider

extension KlaviyoSDK {
    /// Registers the host-supplied closure that produces the auth JWT used for
    /// personalized in-app forms.
    ///
    /// Each call invalidates any cached token and triggers an eager fetch to
    /// warm the cache. Calling again later replaces the previously registered
    /// provider.
    ///
    /// The SDK does not surface acquisition errors to the host — failures are
    /// observable only via OSLog (subsystem
    /// `com.klaviyo.klaviyo-swift-sdk.klaviyoCore`, category `Auth`) and via
    /// form-display behavior.
    ///
    /// - Parameter provider: an `@Sendable` async closure that returns a JWT.
    public func registerAuthTokenProvider(_ provider: @escaping AuthTokenProvider) {
        Task {
            await AuthTokenManager.shared.registerProvider(provider)
        }
    }

    /// Detaches a previously registered auth token provider — e.g. on user
    /// logout.
    ///
    /// Clears the provider reference and tears down all associated token state:
    /// the cached token is discarded and any scheduled proactive refresh or
    /// in-flight fetch is cancelled. After this call, personalized in-app forms
    /// have no token available until a new provider is registered via
    /// ``registerAuthTokenProvider(_:)``.
    public func unregisterAuthTokenProvider() {
        Task {
            await AuthTokenManager.shared.unregisterProvider()
        }
    }
}
