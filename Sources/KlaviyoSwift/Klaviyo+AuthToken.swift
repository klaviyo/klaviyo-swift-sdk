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
    /// Register one long-lived provider during application setup when possible.
    /// The provider should read the current signed-in user whenever the SDK asks
    /// for a token. Registering again replaces the previous provider and warms
    /// the cache with a fresh token.
    ///
    /// The SDK does not surface acquisition errors to the host — failures are
    /// observable only via OSLog (subsystem
    /// `com.klaviyo.klaviyo-swift-sdk.klaviyoCore`, category `Auth`) and via
    /// form-display behavior.
    ///
    /// - Parameter provider: an `@Sendable` async closure that returns a JWT.
    public func registerAuthTokenProvider(_ provider: @escaping AuthTokenProvider) {
        AuthTokenCommandQueue.shared.enqueue(.register(provider))
    }

    /// Detaches a previously registered auth token provider.
    ///
    /// Clears the provider reference and tears down all associated token state:
    /// the cached token is discarded and any scheduled proactive refresh or
    /// in-flight fetch is cancelled. After this call, personalized in-app forms
    /// have no token available until a new provider is registered via
    /// ``registerAuthTokenProvider(_:)``. Hosts that register on login and
    /// unregister on logout can use this as a full teardown; a long-lived
    /// provider registered once during application setup is preferred.
    public func unregisterAuthTokenProvider() {
        AuthTokenCommandQueue.shared.enqueue(.unregister)
    }
}
