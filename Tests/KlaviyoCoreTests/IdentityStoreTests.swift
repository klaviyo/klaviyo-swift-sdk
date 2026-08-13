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
