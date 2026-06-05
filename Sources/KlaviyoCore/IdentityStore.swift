//
//  IdentityStore.swift
//
//  Shared observable SDK state for all Klaviyo SDK modules.
//
//  KlaviyoSwift writes to this store when identity or API key changes.
//  KlaviyoForms, KlaviyoLocation, and other modules can read from it
//  without importing KlaviyoSwift.
//

import Combine
import Foundation

/// Shared, observable SDK state accessible to all Klaviyo SDK modules.
///
/// ## Motivation
/// Before this type, `KlaviyoForms` and `KlaviyoLocation` had to import all of
/// `KlaviyoSwift` to observe identity changes and the SDK API key. `IdentityStore`
/// provides a `KlaviyoCore`-level observation point, enabling those modules to drop
/// their `KlaviyoSwift` dependency for state observation.
///
/// ## Usage
/// **In `KlaviyoSwift` (writer):**
/// ```swift
/// IdentityStore.shared.update(state.identity)
/// IdentityStore.shared.updateAPIKey(state.apiKey)
/// ```
///
/// **In `KlaviyoForms` / `KlaviyoLocation` (readers):**
/// ```swift
/// // Current values
/// let identity = IdentityStore.shared.current
/// let apiKey = IdentityStore.shared.apiKey
///
/// // Combine publishers
/// IdentityStore.shared.publisher.sink { identity in ... }
/// IdentityStore.shared.apiKeyPublisher.sink { apiKey in ... }
///
/// // async/await
/// for await identity in IdentityStore.shared.stream() { ... }
/// ```
public final class IdentityStore: @unchecked Sendable {
    /// The singleton instance written to by `KlaviyoSwift` and read by consumer modules.
    public static let shared = IdentityStore()

    private let subject: CurrentValueSubject<KlaviyoIdentity, Never>
    private let apiKeySubject: CurrentValueSubject<String?, Never>

    init(initial: KlaviyoIdentity = KlaviyoIdentity(), apiKey: String? = nil) {
        subject = CurrentValueSubject(initial)
        apiKeySubject = CurrentValueSubject(apiKey)
    }

    // MARK: - Identity

    /// The current identity snapshot.
    public var current: KlaviyoIdentity { subject.value }

    /// A Combine publisher that emits the current identity and every subsequent update.
    public var publisher: AnyPublisher<KlaviyoIdentity, Never> {
        subject.eraseToAnyPublisher()
    }

    /// An `AsyncStream` of identity updates. Emits the current value immediately
    /// upon subscription, then continues emitting as identity changes.
    public func stream() -> AsyncStream<KlaviyoIdentity> {
        AsyncStream { continuation in
            var cancellable: AnyCancellable?
            cancellable = self.subject.sink { identity in
                continuation.yield(identity)
            }
            continuation.onTermination = { _ in
                cancellable?.cancel()
            }
        }
    }

    /// Updates the stored identity. No-ops if `identity` is identical to the current value.
    ///
    /// - Note: Internal to the SDK. Call sites outside `KlaviyoSwift` should treat this
    ///   store as read-only.
    public func update(_ identity: KlaviyoIdentity) {
        guard identity != current else { return }
        subject.send(identity)
    }

    // MARK: - API Key

    /// The current SDK API key, or `nil` if the SDK has not been initialized yet.
    public var apiKey: String? { apiKeySubject.value }

    /// A Combine publisher that emits the current API key and every subsequent change.
    /// Emits `nil` until the SDK is initialized.
    public var apiKeyPublisher: AnyPublisher<String?, Never> {
        apiKeySubject.eraseToAnyPublisher()
    }

    /// Updates the stored API key. No-ops if the value is identical to the current one.
    ///
    /// - Note: Internal to the SDK. Call sites outside `KlaviyoSwift` should treat this
    ///   store as read-only.
    public func updateAPIKey(_ apiKey: String?) {
        guard apiKey != self.apiKey else { return }
        apiKeySubject.send(apiKey)
    }
}
