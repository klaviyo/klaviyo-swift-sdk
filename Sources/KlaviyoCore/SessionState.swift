//
//  SessionState.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/23/26.
//

import Foundation

/// Core-visible mirror of the SDK's session-scoped initialization signal. `KlaviyoSwift` owns the
/// authoritative `LifecycleState`; it pushes the boolean here so Core code (notably
/// `RequestEnqueuer.route`) can gate on "has `initialize()` started this process?" without depending
/// on `KlaviyoSwift`.
///
/// - Important: Never persisted. Every cold start begins `false`, so a persisted apiKey hydrated from
///   a prior launch does NOT make a pre-init call look post-init (the warm-start / wrong-company bug).
public enum SessionState {
    private static let lock = UnfairLock()
    private static var initialized = false

    /// True once `initialize()` has begun this process (mirrors `LifecycleState != .uninitialized`).
    public static var isInitialized: Bool { lock.withLock { initialized } }

    /// Set by `LifecycleState.beginInitializing()`. Idempotent.
    public static func markInitialized() { lock.withLock { initialized = true } }

    /// Cleared by `LifecycleState.reset()` (test isolation).
    public static func markUninitialized() { lock.withLock { initialized = false } }
}
