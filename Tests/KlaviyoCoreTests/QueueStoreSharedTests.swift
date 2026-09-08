//
//  QueueStoreSharedTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/20/26.
//

@testable import KlaviyoCore
import XCTest

final class QueueStoreSharedTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SDKConfigStore.shared.reset()
        QueueStore.resetShared()
    }

    override func tearDown() {
        SDKConfigStore.shared.reset()
        QueueStore.resetShared()
        super.tearDown()
    }

    func testSharedResolvesIndependentlyOfConfig() {
        // `shared` is usable before any apiKey is configured (buffering pre-apiKey events is handled
        // elsewhere) and always returns the one instance. `current()` gates on the apiKey but
        // resolves to that same shared store once one is set.
        XCTAssertNil(QueueStore.current())
        let store = QueueStore.shared
        store.enqueue(KlaviyoRequest(endpoint: .createProfile("pk-1", CreateProfilePayload(data: .test))))
        XCTAssertEqual(store.count, 1)
        XCTAssertTrue(store === QueueStore.shared, "shared always returns the one instance")
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        XCTAssertTrue(QueueStore.current() === store, "current() resolves to the shared store")
    }

    func testCurrentReturnsSharedInstanceWhenApiKeySet() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        XCTAssertTrue(QueueStore.current() === QueueStore.shared)
    }
}
