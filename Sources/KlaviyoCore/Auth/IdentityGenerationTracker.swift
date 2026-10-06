//
//  IdentityGenerationTracker.swift
//  KlaviyoCore
//

import Combine
import Foundation

/// A profile together with the identity generation it belongs to.
package struct IdentitySnapshot: Equatable {
    /// The most recently observed profile.
    package let profile: ProfileData
    /// Starts at 0 and increases by one on every ``IdentityTransition/replacement`` hop.
    package let generation: UInt64
}

/// Follows a ``VersionedIdentityReading`` and counts the profile replacements it goes through.
///
/// Every profile the source emits is classified against the previous one with
/// ``IdentityTransition/classify(previous:next:)``; a `replacement` hop increments the
/// generation. The profile and generation are updated together, so a reader never sees a
/// new profile with the old generation. Two profiles seen in the same generation describe
/// the same person, however many compatible changes lie between them.
///
/// Updates are delivered synchronously from the source's emission, and ``snapshot()`` also
/// folds in the source's current profile, so a snapshot is up to date whether or not the
/// emission has reached this tracker yet. A value whose sequence number is not newer than the
/// last one seen is ignored, so a late delivery of an older value never moves the tracker back.
final class IdentityGenerationTracker: @unchecked Sendable {
    private let identity: VersionedIdentityReading
    private let lock = NSLock()
    private var state: IdentitySnapshot
    private var lastSequence: UInt64
    private var onChange: (@Sendable () -> Void)?
    private var cancellable: AnyCancellable?

    init(identity: VersionedIdentityReading) {
        self.identity = identity
        let initial = identity.versioned
        state = IdentitySnapshot(profile: initial.profile, generation: 0)
        lastSequence = initial.sequence
        cancellable = identity.versionedPublisher.sink { [weak self] versioned in
            self?.observe(versioned)
        }
    }

    /// Sets the closure called after every observed profile change, outside the tracker's
    /// lock, with the tracker already updated.
    func setOnChange(_ onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.onChange = onChange
    }

    /// Starts a new generation without a profile change, so state bound to the previous one is
    /// no longer current.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        state = IdentitySnapshot(profile: state.profile, generation: state.generation + 1)
    }

    /// The latest profile and the generation it belongs to.
    func snapshot() -> IdentitySnapshot {
        observe(identity.versioned)
    }

    @discardableResult
    private func observe(_ versioned: VersionedProfile) -> IdentitySnapshot {
        lock.lock()
        guard versioned.sequence > lastSequence else {
            defer { lock.unlock() }
            return state
        }
        lastSequence = versioned.sequence
        let transition = IdentityTransition.classify(previous: state.profile, next: versioned.profile)
        guard transition != .unchanged else {
            defer { lock.unlock() }
            return state
        }
        let generation = transition == .replacement ? state.generation + 1 : state.generation
        state = IdentitySnapshot(profile: versioned.profile, generation: generation)
        let updated = state
        let handler = onChange
        lock.unlock()
        handler?()
        return updated
    }
}
