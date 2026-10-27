//
//  IdentityStoreVersionTests.swift
//  klaviyo-swift-sdk
//
//  Tests the versioned identity seam: sequence monotonicity, hydration interplay,
//  and that a late stale read cannot move an ``IdentityGenerationTracker`` back.
//

@testable import KlaviyoCore
import Combine
import XCTest

final class IdentityStoreVersionTests: XCTestCase {
    private var fileIO: FileIODouble!
    private static let mintedAnonId = "00000000-0000-0000-0000-0000000000AA"

    override func setUp() {
        super.setUp()
        fileIO = FileIODouble()
        environment = fileIO.makeEnvironment()
        environment.uuid = { UUID(uuidString: Self.mintedAnonId)! }
    }

    override func tearDown() {
        environment = KlaviyoEnvironment.test()
        fileIO = nil
        super.tearDown()
    }

    // 0: a seeded store keeps its seed through first read and tracker creation.
    func testSeededIdentitySurvivesFirstRead() {
        let seed = ProfileData(email: "a@example.com", anonymousId: "anon")
        let store = IdentityStore(initialIdentity: seed)
        XCTAssertEqual(store.versioned.profile, seed)
        XCTAssertEqual(IdentityGenerationTracker(identity: store).snapshot().profile, seed)
    }

    // 1: sequence strictly increases and matches emission order under concurrent writers.
    func testSequenceIsStrictlyIncreasingUnderConcurrentWrites() {
        let store = IdentityStore(initialIdentity: ProfileData())
        var seen = [UInt64]()
        let seenLock = NSLock()
        let subscription = store.versionedPublisher.sink { versioned in
            seenLock.lock()
            seen.append(versioned.sequence)
            seenLock.unlock()
        }
        DispatchQueue.concurrentPerform(iterations: 200) { iteration in
            if iteration.isMultiple(of: 2) {
                store.update(ProfileData(email: "u\(iteration)@example.com"))
            } else {
                store.mutate { $0.externalId = "e\(iteration)" }
            }
        }
        subscription.cancel()
        XCTAssertEqual(seen.count, 201) // initial + 200 writes
        XCTAssertEqual(seen, seen.sorted())
        XCTAssertEqual(Set(seen).count, seen.count)
    }

    // 2: a tracker created before first hydration sees the hydrated profile.
    func testTrackerCreatedBeforeHydrationSeesHydratedProfile() {
        let store = IdentityStore() // not seeded: hydrates lazily and mints an anonymousId
        let tracker = IdentityGenerationTracker(identity: store)
        XCTAssertEqual(tracker.snapshot().profile.anonymousId, Self.mintedAnonId)
    }

    // 3: token-only writes neither bump the sequence nor emit a profile.
    func testPushTokenWriteDoesNotAdvanceSequenceOrEmitProfile() {
        let store = IdentityStore(initialIdentity: ProfileData(email: "a@example.com"))
        let before = store.versioned.sequence
        var emissions = 0
        let subscription = store.versionedPublisher.dropFirst().sink { _ in emissions += 1 }
        store.updatePushToken(nil)
        subscription.cancel()
        XCTAssertEqual(store.versioned.sequence, before)
        XCTAssertEqual(emissions, 0)
    }

    // 4: the sequence continues across reset() and rehydration.
    func testSequenceContinuesAcrossReset() {
        let store = IdentityStore(initialIdentity: ProfileData())
        store.update(ProfileData(email: "a@example.com"))
        let beforeReset = store.versioned.sequence
        store.reset()
        XCTAssertGreaterThan(store.versioned.sequence, beforeReset)
        let afterRehydrate = store.versioned.sequence
        store.update(ProfileData(email: "b@example.com"))
        XCTAssertGreaterThan(store.versioned.sequence, afterRehydrate)
    }

    // 5: post-reset rehydration mints an anonymousId without emitting it.
    func testPostResetRehydrationDoesNotEmitMintedAnonymousId() {
        let store = IdentityStore(initialIdentity: ProfileData(email: "a@example.com"))
        store.reset()
        var emitted = [ProfileData]()
        let subscription = store.versionedPublisher.dropFirst().sink { emitted.append($0.profile) }
        _ = store.current // triggers rehydration
        subscription.cancel()
        XCTAssertTrue(emitted.isEmpty)
        XCTAssertEqual(store.current.anonymousId, Self.mintedAnonId)
    }

    // 6: a stale versioned read folded into the tracker after a newer observation is ignored,
    // so the snapshot cannot regress. Uses a stub source so the stale value is actually
    // delivered to the tracker, not just dropped by the test.
    func testStaleVersionedValueDoesNotRegressTracker() {
        let stub = VersionedIdentityStub(initial: VersionedProfile(profile: ProfileData(), sequence: 0))
        let tracker = IdentityGenerationTracker(identity: stub)

        // (2) the tracker observes sequence 1, a replacement profile: generation becomes 1.
        stub.send(VersionedProfile(profile: ProfileData(email: "b@example.com"), sequence: 1))
        let afterReplacement = tracker.snapshot()
        XCTAssertEqual(afterReplacement.generation, 1)
        XCTAssertEqual(afterReplacement.profile.email, "b@example.com")
        XCTAssertEqual(afterReplacement.profile, ProfileData(email: "b@example.com"))

        // (3) `versioned` now reports an older value carrying the seed profile (a stale read);
        // folding it in must not move the tracker back. Its sequence is 0 — strictly older than
        // the observed sequence 1 — so this fails if the tracker's not-newer guard is removed.
        stub.versioned = VersionedProfile(profile: ProfileData(email: "a@example.com"), sequence: 0)
        XCTAssertEqual(tracker.snapshot(), afterReplacement)
    }
}

/// A test-only ``VersionedIdentityReading`` whose publisher the test drives directly and whose
/// `versioned` reader can be made to report an older value than what was last published —
/// simulating a stale read of the real store.
private final class VersionedIdentityStub: VersionedIdentityReading {
    var versioned: VersionedProfile

    private let subject: CurrentValueSubject<VersionedProfile, Never>

    init(initial: VersionedProfile) {
        versioned = initial
        subject = CurrentValueSubject(initial)
    }

    func send(_ value: VersionedProfile) {
        subject.send(value)
    }

    var versionedPublisher: AnyPublisher<VersionedProfile, Never> {
        subject.eraseToAnyPublisher()
    }

    // IdentityReading surface; unused by the tracker.
    var current: ProfileData { subject.value.profile }
    var pushToken: PushTokenData? { nil }
    var publisher: AnyPublisher<ProfileData, Never> { subject.map(\.profile).eraseToAnyPublisher() }
    func stream() -> AsyncStream<ProfileData> { AsyncStream { _ in } }
}
