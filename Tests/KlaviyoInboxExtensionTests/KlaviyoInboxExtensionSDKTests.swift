//
//  KlaviyoInboxExtensionSDKTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxExtension
import KlaviyoInboxTestSupport
import XCTest

/// The extension reads only what is on disk: no `KlaviyoInbox`, no `KlaviyoSDK`, no registration call
/// in this process. Fixtures are written by hand so the on-disk format is pinned independently of
/// the writer.
final class KlaviyoInboxExtensionSDKTests: XCTestCase {
    private let groupId = InboxTemporaryGroup.identifier
    private var temp: InboxTemporaryGroup!

    override func setUp() {
        super.setUp()
        temp = InboxTemporaryGroup()
    }

    override func tearDown() {
        temp.remove()
        temp = nil
        super.tearDown()
    }

    private func writeFixture(_ json: String) throws {
        let directory = temp.root
            .appendingPathComponent(groupId, isDirectory: true)
            .appendingPathComponent("KlaviyoInbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: directory.appendingPathComponent("klaviyo-inbox-config.json"))
    }

    private func lookup(group: InboxAppGroup? = nil) -> InboxEnablement {
        KlaviyoInboxExtensionSDK.enablement(group: group ?? temp.group)
    }

    func testInstalledButNeverRegistered() {
        XCTAssertEqual(lookup(), .neverRegistered)
    }

    func testEnabled() throws {
        try writeFixture(#"{"version":1,"enabled":true,"localRetentionLimit":25}"#)
        XCTAssertEqual(lookup(), .enabled(localRetentionLimit: 25))
    }

    func testDisabled() throws {
        try writeFixture(#"{"version":1,"enabled":false,"localRetentionLimit":25}"#)
        XCTAssertEqual(lookup(), .disabled)
    }

    func testUnreachableGroupIsTreatedAsNeverRegistered() {
        XCTAssertEqual(lookup(group: InboxTemporaryGroup.unreachable), .neverRegistered)
    }

    func testMissingInfoPlistEntryIsTreatedAsNeverRegistered() {
        XCTAssertEqual(lookup(group: InboxTemporaryGroup.missingIdentifier), .neverRegistered)
    }

    func testMalformedFileFailsClosed() throws {
        try writeFixture("not json")
        XCTAssertEqual(lookup(), .disabled)
    }
}
