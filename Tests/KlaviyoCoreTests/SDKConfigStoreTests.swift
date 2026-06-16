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
    func testInitialAPIKeyIsNil() {
        let store = SDKConfigStore()
        XCTAssertNil(store.apiKey)
    }

    func testUpdateAPIKeyReflectsSynchronously() {
        let store = SDKConfigStore()

        store.updateAPIKey("company-123")

        XCTAssertEqual(store.apiKey, "company-123")
    }

    func testUpdateAPIKeyEmitsOnPublisher() {
        let store = SDKConfigStore()

        var received: [String?] = []
        let cancellable = store.apiKeyPublisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        store.updateAPIKey("company-123")

        // CurrentValueSubject replays the current value on subscribe, then the update.
        XCTAssertEqual(received, [nil, "company-123"])
    }
}

// Compile-time proof that a consumer can conform to the read interface alone,
// with no access to `updateAPIKey(_:)`.
private struct MockConfigReader: ConfigReading {
    var apiKey: String?
    var apiKeyPublisher: AnyPublisher<String?, Never>
}
