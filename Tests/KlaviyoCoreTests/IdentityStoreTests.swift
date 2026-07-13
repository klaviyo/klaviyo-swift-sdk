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
    func testInitialStateIsEmptyProfileData() {
        let store = IdentityStore()
        XCTAssertEqual(store.current, ProfileData())
    }

    func testUpdateReflectsSynchronouslyOnCurrent() {
        let store = IdentityStore()
        let identity = ProfileData(email: "test@example.com", anonymousId: "anon-1")

        store.update(identity)

        XCTAssertEqual(store.current, identity)
    }

    func testUpdateEmitsOnPublisher() {
        let store = IdentityStore()
        let identity = ProfileData(email: "test@example.com")

        var received: [ProfileData] = []
        let cancellable = store.publisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        store.update(identity)

        // CurrentValueSubject replays the current value on subscribe, then the update.
        XCTAssertEqual(received, [ProfileData(), identity])
    }

    func testStreamEmitsUpdates() async {
        let store = IdentityStore()
        let identity = ProfileData(externalId: "ext-1")

        let stream = store.stream()
        store.update(identity)

        var received: [ProfileData] = []
        for await value in stream {
            received.append(value)
            if value == identity { break }
        }

        XCTAssertEqual(received, [ProfileData(), identity])
    }

    // reset(): store should return to default empty ProfileData after being updated.
    func testResetRestoresDefaultProfileData() {
        let store = IdentityStore()
        store.update(ProfileData(email: "test@example.com", anonymousId: "anon-1"))

        store.reset()

        XCTAssertEqual(store.current, ProfileData())
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
        let (a, b) = await (receivedA, receivedB)

        // Each consumer sees the initial empty value followed by every update, in order.
        let expected = [ProfileData()] + updates
        XCTAssertEqual(a, expected)
        XCTAssertEqual(b, expected)
    }
}

// Compile-time proof that a consumer can conform to the read interface alone,
// with no access to `update(_:)`.
private struct MockIdentityReader: IdentityReading {
    var current: ProfileData
    var publisher: AnyPublisher<ProfileData, Never>
    func stream() -> AsyncStream<ProfileData> {
        AsyncStream { $0.finish() }
    }
}
