//
//  IdentityStore.swift
//
//  Shared observable identity state for all Klaviyo SDK modules.
//
//  KlaviyoSwift writes to this store when identity changes.
//  KlaviyoForms, KlaviyoLocation, and other modules can read from it
//  without importing KlaviyoSwift.
//

import Combine
import Foundation

/// Shared, observable identity state accessible to all Klaviyo SDK modules.
///
/// ## Motivation
/// Before this type, `KlaviyoForms` and `KlaviyoLocation` had to import all of
/// `KlaviyoSwift` to observe identity changes. `IdentityStore` provides a
/// `KlaviyoCore`-level observation point, enabling those modules to drop their
/// `KlaviyoSwift` dependency.
///
/// ## Usage
/// **In `KlaviyoSwift` (writer):**
/// ```swift
/// IdentityStore.shared.update(state.identity)
/// ```
///
/// **In `KlaviyoForms` / `KlaviyoLocation` (readers):**
/// ```swift
/// // Combine
/// IdentityStore.shared.publisher
///     .sink { identity in ... }
///
/// // async/await
/// for await identity in IdentityStore.shared.stream() { ... }
/// ```
public final class IdentityStore: @unchecked Sendable {
    /// The singleton instance written to by `KlaviyoSwift` and read by consumer modules.
    public static let shared = IdentityStore()

    private let subject: CurrentValueSubject<KlaviyoIdentity, Never>

    init(initial: KlaviyoIdentity = KlaviyoIdentity()) {
        subject = CurrentValueSubject(initial)
    }

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
}
