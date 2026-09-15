//
//  IdentityStoreTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

@testable import KlaviyoCore
import Combine
import XCTest

final class IdentityStoreTests: XCTestCase {
    private var fileIO: FileIODouble!

    private static let mintedAnonId = "00000000-0000-0000-0000-0000000000AA"

    private var mintedProfile: ProfileData {
        ProfileData(anonymousId: Self.mintedAnonId)
    }

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

    // First access hydrates with no file present, so IdentityStore mints an anonymousId.
    func testInitialAccessMintsAnonymousId() {
        let store = IdentityStore()
        XCTAssertNil(store.current.email)
        XCTAssertNil(store.current.phoneNumber)
        XCTAssertNil(store.current.externalId)
        XCTAssertNotNil(store.current.anonymousId)
        XCTAssertEqual(store.current.anonymousId, Self.mintedAnonId)
    }

    func testUpdateReflectsSynchronouslyOnCurrent() {
        let store = IdentityStore()
        let identity = ProfileData(email: "test@example.com", anonymousId: "anon-1")

        store.update(identity)

        XCTAssertEqual(store.current, identity)
    }

    func testUpdateEmitsOnPublisher() {
        let store = IdentityStore()
        let identity = ProfileData(email: "test@example.com", anonymousId: Self.mintedAnonId)

        var received: [ProfileData] = []
        let cancellable = store.publisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        store.update(identity)

        // CurrentValueSubject replays the current (minted) value on subscribe, then the update.
        XCTAssertEqual(received, [mintedProfile, identity])
    }

    func testStreamEmitsUpdates() async {
        let store = IdentityStore()
        let identity = ProfileData(externalId: "ext-1", anonymousId: Self.mintedAnonId)

        let stream = store.stream()
        store.update(identity)

        var received: [ProfileData] = []
        for await value in stream {
            received.append(value)
            if value == identity { break }
        }

        XCTAssertEqual(received, [mintedProfile, identity])
    }

    // reset() clears identifiers and re-arms hydration; a subsequent read re-mints.
    func testResetRestoresDefaultProfileData() {
        let store = IdentityStore()
        store.update(ProfileData(email: "test@example.com", anonymousId: "anon-1"))

        store.reset()

        XCTAssertNil(store.current.email)
        XCTAssertNil(store.current.phoneNumber)
        XCTAssertNil(store.current.externalId)
        // reset re-arms hydration, so the next read freshly mints a (non-nil) anonymousId
        // that is not the pre-reset "anon-1".
        XCTAssertNotNil(store.current.anonymousId)
        XCTAssertNotEqual(store.current.anonymousId, "anon-1")
        XCTAssertEqual(store.current.anonymousId, Self.mintedAnonId)
    }

    func testStreamDeliversAllUpdatesToConcurrentConsumersNoDrops() async {
        let store = IdentityStore()
        let updates = (0..<100).map { ProfileData(externalId: "id-\($0)") }

        // Subscribe both consumers before any writes so all emissions are buffered.
        let streamA = store.stream()
        let streamB = store.stream()

        for update in updates {
            store.update(update)
        }

        func collect(_ stream: AsyncStream<ProfileData>) async -> [ProfileData] {
            var received: [ProfileData] = []
            for await value in stream {
                received.append(value)
                if value == updates.last { break }
            }
            return received
        }

        async let receivedA = collect(streamA)
        async let receivedB = collect(streamB)
        let (resultA, resultB) = await (receivedA, receivedB)

        // Each consumer sees the initial (minted) value followed by every update, in order.
        let expected = [mintedProfile] + updates
        XCTAssertEqual(resultA, expected)
        XCTAssertEqual(resultB, expected)
    }

    // `mutate` reads-modifies-persists-emits atomically: clearing one field leaves the others intact,
    // persists to disk, and emits exactly one new value. This is the primitive the RequestQueue's 4xx
    // field-clear uses instead of a read-then-`update` (which is a TOCTOU across concurrent writers).
    func testMutateAtomicallyClearsSelectedFieldOnly() {
        let store = IdentityStore()
        let seeded = ProfileData(
            email: "a@b.com",
            phoneNumber: "+15551234567",
            externalId: "ext-1",
            anonymousId: Self.mintedAnonId
        )
        store.update(seeded)

        var received: [ProfileData] = []
        let cancellable = store.publisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        store.mutate { profile in
            profile.email = nil
        }

        let expected = ProfileData(
            email: nil,
            phoneNumber: "+15551234567",
            externalId: "ext-1",
            anonymousId: Self.mintedAnonId
        )
        // In-memory current reflects the mutation; only `email` was cleared.
        XCTAssertEqual(store.current, expected)
        // A fresh store hydrates from disk — the mutation was persisted.
        XCTAssertEqual(IdentityStore().current, expected)
        // Exactly one emission for the mutate (after the sink's replay of the pre-mutate value).
        XCTAssertEqual(received, [seeded, expected])
    }

    // Writer-vs-writer safety: under many concurrent writers, the value on disk must equal the last
    // value emitted to subscribers. The pre-Task-0 store persisted under the data lock but emitted
    // outside it, so two writers could persist in one order and emit in another — disk and last-emit
    // diverge. Serializing each write (persist THEN emit) end-to-end closes that gap.
    func testConcurrentWritesKeepDiskAndLastEmitInSync() {
        let store = IdentityStore()

        let emitLock = NSLock()
        var received: [ProfileData] = []
        let cancellable = store.publisher.sink { value in
            emitLock.lock()
            received.append(value)
            emitLock.unlock()
        }
        defer { cancellable.cancel() }

        DispatchQueue.concurrentPerform(iterations: 500) { iteration in
            store.update(ProfileData(externalId: "id-\(iteration)", anonymousId: Self.mintedAnonId))
        }

        emitLock.lock()
        let lastEmitted = received.last
        emitLock.unlock()

        // A fresh store hydrates from disk — this is the persisted (source-of-truth) value.
        let reloadedFromDisk = IdentityStore().current

        XCTAssertEqual(lastEmitted, reloadedFromDisk)
        // The in-memory view agrees with disk too.
        XCTAssertEqual(store.current, reloadedFromDisk)
    }
}

// Compile-time proof that a consumer can conform to the read interface alone,
// with no access to `update(_:)`.
private struct MockIdentityReader: IdentityReading {
    var current: ProfileData
    var pushToken: PushTokenData?
    var publisher: AnyPublisher<ProfileData, Never>
    func stream() -> AsyncStream<ProfileData> {
        AsyncStream { $0.finish() }
    }
}
