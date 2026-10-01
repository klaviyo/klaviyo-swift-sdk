//
//  Klaviyo+AuthToken.swift
//  KlaviyoSwift
//
//  Created by Andrew Balmer on 2026-05-14.
//

import Foundation
import KlaviyoCore

@MainActor
private enum AuthTokenProviderSequencer {
    static var tail: Task<Void, Never>?

    nonisolated static func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        DispatchQueue.main.async { @MainActor in
            let previous = tail
            tail = Task {
                await previous?.value
                await operation()
            }
        }
    }
}

/// Re-exports ``KlaviyoCore/AuthTokenProvider`` so host code that imports only
/// `KlaviyoSwift` can reference the closure type without a second import.
public typealias AuthTokenProvider = KlaviyoCore.AuthTokenProvider

extension KlaviyoSDK {
    /// Registers the host-supplied closure that produces the auth JWT used for
    /// personalized in-app forms.
    ///
    /// Each call invalidates any cached token and, for an identified profile (one with an
    /// email, phone number or external ID), triggers an eager fetch to warm the cache. If
    /// the profile is not identified yet, the fetch runs once the profile becomes identified.
    /// The provider is never called while the profile has no identifier. Calling again later
    /// replaces the previously registered provider.
    ///
    /// Register and unregister calls are applied in the order they are made,
    /// so the last call always determines the provider in effect. Ordering is
    /// guaranteed for calls made from the same thread, or otherwise ordered by
    /// the caller. Calls take effect asynchronously, shortly after they return.
    ///
    /// The SDK does not surface acquisition errors to the host — failures are
    /// observable only via OSLog (subsystem
    /// `com.klaviyo.klaviyo-swift-sdk.klaviyoCore`, category `Auth`, and only
    /// when SDK logging is enabled) and via form-display behavior.
    ///
    /// - Parameter provider: an `@Sendable` async closure that returns a JWT.
    ///   The SDK caches the returned token and calls the provider again when it
    ///   needs a new one, for example before expiry or after the server rejected
    ///   the current token. Return a freshly issued token on every call; don't
    ///   return one cached from a previous call.
    public func registerAuthTokenProvider(_ provider: @escaping AuthTokenProvider) {
        AuthTokenProviderSequencer.enqueue {
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
    ///
    /// Applied in call order relative to ``registerAuthTokenProvider(_:)``, so
    /// unregistering and then registering again leaves the new provider active.
    /// Unlike Android, where these calls apply synchronously, iOS applies them
    /// asynchronously in call order.
    public func unregisterAuthTokenProvider() {
        AuthTokenProviderSequencer.enqueue {
            await AuthTokenManager.shared.unregisterProvider()
        }
    }
}
