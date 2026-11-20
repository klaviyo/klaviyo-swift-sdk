//
//  ProfileResetSignal.swift
//  klaviyo-swift-sdk
//

import Combine
import Foundation

/// Tells modules that cannot be imported from `KlaviyoSwift`, such as `KlaviyoInbox`, that the app reset
/// the profile, so they can drop the previous profile's on-device data.
///
/// Two things carry a reset, because a listener may not exist yet when it happens:
/// - A live signal, ``resets()``, for a listener that is already running. It does not replay.
/// - A persisted marker, ``pendingMarker()``, written before the live signal is sent. A listener that
///   starts later, in this launch or the next, reads it and acts on a reset it missed. It stays until the
///   listener has acted and calls ``acknowledge(_:)``, so a failed clear is tried again.
package enum ProfileResetSignal {
    private struct PersistedMarker: Codable, Equatable {
        static let currentVersion = 1
        var version: Int
        var id: UUID
    }

    private static let subject = PassthroughSubject<Void, Never>()
    /// Serializes the marker's read, write and removal, so an acknowledgement never removes a newer marker.
    private static let lock = UnfairLock()

    /// Records a reset and tells every active listener. Called by `KlaviyoSwift` on every `resetProfile()`
    /// that is not dropped, including one that changes nothing because the profile was already anonymous.
    package static func publish() {
        lock.withLock {
            savePersisted(
                PersistedMarker(version: PersistedMarker.currentVersion, id: environment.uuid()),
                fileName: StoreFile.profileResetPending
            )
        }
        // Outside the lock: Combine delivers to listeners synchronously.
        subject.send(())
    }

    /// A stream with one element per reset that happens after this call. Each call is independent, and
    /// ending the iteration ends the subscription. Resets that arrive while an element is being handled
    /// collapse into one more element, which is enough because handling one drops everything.
    ///
    /// It does not replay, so a listener that starts late also reads ``pendingMarker()``. Subscribe before
    /// reading the marker so a reset between the two is not missed.
    package static func resets() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let cancellable = subject.sink { continuation.yield(()) }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// The id of the reset no listener has acknowledged yet, or nil when there is none.
    package static func pendingMarker() -> UUID? {
        lock.withLock {
            loadPersisted(PersistedMarker.self, fileName: StoreFile.profileResetPending)?.id
        }
    }

    /// Removes the marker, unless a newer reset replaced it since `id` was read.
    package static func acknowledge(_ id: UUID) {
        lock.withLock {
            guard loadPersisted(PersistedMarker.self, fileName: StoreFile.profileResetPending)?.id == id else { return }
            removePersisted(fileName: StoreFile.profileResetPending)
        }
    }

    /// Test-support: drops the marker.
    package static func reset() {
        lock.withLock { removePersisted(fileName: StoreFile.profileResetPending) }
    }
}
