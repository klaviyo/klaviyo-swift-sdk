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
    func testInitialConfigIsEmpty() {
        let store = SDKConfigStore()
        XCTAssertEqual(store.current, KlaviyoConfig())
        XCTAssertNil(store.current.apiKey)
    }

    func testUpdateReflectsSynchronously() {
        let store = SDKConfigStore()

        store.update(KlaviyoConfig(apiKey: "company-123"))

        XCTAssertEqual(store.current.apiKey, "company-123")
    }

    func testUpdateEmitsOnPublisher() {
        let store = SDKConfigStore()

        var received: [KlaviyoConfig] = []
        let cancellable = store.publisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        store.update(KlaviyoConfig(apiKey: "company-123"))

        // CurrentValueSubject replays the current value on subscribe, then the update.
        XCTAssertEqual(received, [KlaviyoConfig(), KlaviyoConfig(apiKey: "company-123")])
    }

    func testStreamYieldsCurrentValueThenUpdates() async {
        let store = SDKConfigStore()

        let task = Task<[KlaviyoConfig], Never> {
            var received: [KlaviyoConfig] = []
            for await config in store.stream() {
                received.append(config)
                if received.count == 2 { break }
            }
            return received
        }

        // Give the stream a moment to subscribe and replay the current value.
        try? await Task.sleep(nanoseconds: 50_000_000)
        store.update(KlaviyoConfig(apiKey: "company-123"))

        let received = await task.value
        XCTAssertEqual(received, [KlaviyoConfig(), KlaviyoConfig(apiKey: "company-123")])
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
