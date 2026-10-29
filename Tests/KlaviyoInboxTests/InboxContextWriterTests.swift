//
//  InboxContextWriterTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class InboxContextWriterTests: XCTestCase {
    private var appGroup: InboxAppGroup!

    override func setUp() {
        super.setUp()
        appGroup = InboxStoreFixtures.temporaryAppGroup()
    }

    /// `KlaviyoSwift` finds the writer by this exact name, so the spelling is part of the contract.
    func testTheWriterIsFoundByTheNameKlaviyoSwiftLooksUp() {
        XCTAssertNotNil(NSClassFromString("InboxContextWriter"))
    }

    func testTheWriterAnswersToTheSelectorKlaviyoSwiftCalls() throws {
        let writer = try XCTUnwrap(NSClassFromString("InboxContextWriter") as? NSObject.Type)
        XCTAssertTrue(writer.responds(to: NSSelectorFromString("writeWithApiKey:")))
    }

    func testANewKeyIsWrittenToTheAppGroup() {
        InboxContextWriter.write(apiKey: "AbC123", appGroup: appGroup)
        XCTAssertEqual(InboxContext.read(appGroup: appGroup)?.companyID, "AbC123")
    }

    func testTheSameKeyIsNotWrittenAgain() {
        XCTAssertEqual(InboxContextWriter.write(apiKey: "AbC123", appGroup: appGroup), .written)
        XCTAssertEqual(InboxContextWriter.write(apiKey: "AbC123", appGroup: appGroup), .unchanged)
    }

    func testAChangedKeyReplacesTheOldOne() {
        InboxContextWriter.write(apiKey: "AbC123", appGroup: appGroup)
        InboxContextWriter.write(apiKey: "XyZ789", appGroup: appGroup)
        XCTAssertEqual(InboxContext.read(appGroup: appGroup)?.companyID, "XyZ789")
    }

    func testAnEmptyKeyWritesNothing() {
        XCTAssertEqual(InboxContextWriter.write(apiKey: "", appGroup: appGroup), .unavailable)
        XCTAssertNil(InboxContext.read(appGroup: appGroup))
    }

    func testAnUnresolvedAppGroupWritesNothing() {
        let unreachable = InboxAppGroup(identifier: { "group.test" }, containerURL: { _ in nil })
        XCTAssertEqual(InboxContextWriter.write(apiKey: "AbC123", appGroup: unreachable), .unavailable)
    }
}
