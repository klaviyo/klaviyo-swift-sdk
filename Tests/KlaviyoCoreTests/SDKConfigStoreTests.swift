//
//  SDKConfigStoreTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

@testable import KlaviyoCore
import Combine
import XCTest

final class SDKConfigStoreTests: XCTestCase {
    private static let apiKey = "company-123"
    private var fileIO: FileIODouble!

    override func setUp() {
        super.setUp()
        fileIO = FileIODouble()
        environment = fileIO.makeEnvironment()
    }

    override func tearDown() {
        environment = KlaviyoEnvironment.test()
        fileIO = nil
        super.tearDown()
    }

    func testInitialConfigIsEmpty() {
        let store = SDKConfigStore()
        XCTAssertEqual(store.current, KlaviyoConfig())
        XCTAssertNil(store.current.apiKey)
    }

    func testUpdateReflectsSynchronously() {
        let store = SDKConfigStore()

        store.update(KlaviyoConfig(apiKey: Self.apiKey))

        XCTAssertEqual(store.current.apiKey, Self.apiKey)
    }

    func testUpdateEmitsOnPublisher() {
        let store = SDKConfigStore()

        var received: [KlaviyoConfig] = []
        let cancellable = store.publisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        store.update(KlaviyoConfig(apiKey: Self.apiKey))

        // CurrentValueSubject replays the current value on subscribe, then the update.
        XCTAssertEqual(received, [KlaviyoConfig(), KlaviyoConfig(apiKey: Self.apiKey)])
    }

    // reset(): store should return to default empty KlaviyoConfig after being updated.
    func testResetRestoresDefaultConfig() {
        let store = SDKConfigStore()
        store.update(KlaviyoConfig(apiKey: "company-123"))

        store.reset()

        XCTAssertEqual(store.current, KlaviyoConfig())
        XCTAssertNil(store.current.apiKey)
    }

    func testStreamYieldsCurrentValueThenUpdates() async {
        let store = SDKConfigStore()
        var iterator = store.stream().makeAsyncIterator()

        // The stream replays the current value on subscribe before any update.
        let initial = await iterator.next()
        XCTAssertEqual(initial, KlaviyoConfig())

        store.update(KlaviyoConfig(apiKey: Self.apiKey))

        let updated = await iterator.next()
        XCTAssertEqual(updated, KlaviyoConfig(apiKey: Self.apiKey))
    }
}

// Compile-time proof that a consumer can conform to the read interface alone,
// with no access to `update(_:)`.
private struct MockConfigReader: ConfigReading {
    var current: KlaviyoConfig
    var publisher: AnyPublisher<KlaviyoConfig, Never>
    func stream() -> AsyncStream<KlaviyoConfig> {
        AsyncStream { $0.finish() }
    }
}
