//
//  InboxWriterBridgeTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

@testable import KlaviyoSwift
import Foundation
import XCTest

/// A stand-in for the `KlaviyoInbox` writer, registered under its own name so it cannot collide with
/// the real `InboxContextWriter` when both are linked into one test process.
@objc(KlaviyoSwiftTestInboxWriterStub)
final class InboxWriterStub: NSObject {
    nonisolated(unsafe) static var receivedKeys: [String] = []

    @objc
    class func write(apiKey: String) {
        receivedKeys.append(apiKey)
    }
}

final class InboxWriterBridgeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        InboxWriterStub.receivedKeys = []
    }

    /// The spelling `KlaviyoInbox` registers its class under, pinned from this side as well.
    func testTheBridgeLooksUpTheNameAndSelectorKlaviyoInboxProvides() {
        XCTAssertEqual(InboxWriterBridge.className, "InboxContextWriter")
        XCTAssertEqual(InboxWriterBridge.selector, "writeWithApiKey:")
    }

    func testNotifyCallsTheWriterWithTheAPIKey() {
        InboxWriterBridge.notify(apiKey: "AbC123", className: "KlaviyoSwiftTestInboxWriterStub")
        XCTAssertEqual(InboxWriterStub.receivedKeys, ["AbC123"])
    }

    func testNotifyIsANoOpWhenNoClassIsRegisteredUnderTheName() {
        InboxWriterBridge.notify(apiKey: "AbC123", className: "NoSuchInboxWriter")
        XCTAssertTrue(InboxWriterStub.receivedKeys.isEmpty)
    }

    func testNotifyWithTheDefaultNameDoesNothingWhenKlaviyoInboxIsNotLinked() throws {
        // `swift test` builds every test target into one bundle, so KlaviyoInbox can be linked here.
        try XCTSkipIf(
            NSClassFromString(InboxWriterBridge.className) != nil,
            "KlaviyoInbox is linked into this test bundle."
        )
        InboxWriterBridge.notify(apiKey: "AbC123")
        XCTAssertTrue(InboxWriterStub.receivedKeys.isEmpty)
    }
}
