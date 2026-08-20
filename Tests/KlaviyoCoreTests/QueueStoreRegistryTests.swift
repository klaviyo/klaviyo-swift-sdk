//
//  QueueStoreRegistryTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/20/26.
//

@testable import KlaviyoCore
import XCTest

final class QueueStoreRegistryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SDKConfigStore.shared.reset()
        QueueStore.resetRegistry()
    }

    override func tearDown() {
        SDKConfigStore.shared.reset()
        QueueStore.resetRegistry()
        super.tearDown()
    }

    func testStoreForKeyResolvesIndependentlyOfConfig() {
        // No apiKey set, yet store(for:) returns a usable store for the captured key — proving queue
        // resolution never re-reads SDKConfigStore and so can't race a config change. current()
        // delegates to it for the active key, returning the same cached instance.
        XCTAssertNil(QueueStore.current())
        let store = QueueStore.store(for: "pk-1")
        store.enqueue(KlaviyoRequest(endpoint: .createProfile("pk-1", CreateProfilePayload(data: .test))))
        XCTAssertEqual(store.count, 1)
        XCTAssertTrue(store === QueueStore.store(for: "pk-1"), "same key returns the cached instance")
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        XCTAssertTrue(QueueStore.current() === store, "current() resolves to store(for: activeKey)")
    }
}
