//
//  UnfairLock.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

import os

/// A thin reference-type wrapper around `os_unfair_lock`, providing a scoped `withLock` API.
///
/// `os_unfair_lock` is a value type that must never be copied or moved; boxing it in a `final class`
/// keeps its address stable and makes misuse impossible at the call site. The `withLock` closure also
/// enforces balanced lock/unlock via `defer`. This is effectively a hand-rolled `OSAllocatedUnfairLock`
/// for the SDK's iOS 13 deployment floor (the system wrapper requires iOS 16+).
///
/// Semantics inherited from `os_unfair_lock`: not recursive (re-entering `withLock` on the same thread
/// deadlocks) and not fair, but priority-inversion safe (the kernel can boost the lock holder).
///
/// This is the SDK's single first-party locking primitive for guarding simple critical sections —
/// prefer it over `NSLock`/GCD for in-memory state. `@unchecked Sendable` is sound: the boxed
/// `os_unfair_lock` is the synchronization, and `withLock` is its only access path.
final class UnfairLock: @unchecked Sendable {
    private var _lock = os_unfair_lock_s()

    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return try body()
    }
}
