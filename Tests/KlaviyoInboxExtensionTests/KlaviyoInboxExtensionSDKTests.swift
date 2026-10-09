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

#if canImport(Testing)
import Testing

/// The extension reads only what is on disk: no `KlaviyoInbox`, no `KlaviyoSDK`, no registration call
/// in this process. Fixtures are written by hand so the on-disk format is pinned independently of
/// the writer.
final class KlaviyoInboxExtensionSDKTests {
    private let temp = InboxTemporaryGroup()

    deinit {
        temp.remove()
    }

    private func writeFixture(_ json: String) throws {
        let directory = temp.root
            .appendingPathComponent(InboxTemporaryGroup.identifier, isDirectory: true)
            .appendingPathComponent("KlaviyoInbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: directory.appendingPathComponent("klaviyo-inbox-config.json"))
    }

    private func lookup(group: InboxAppGroup? = nil) -> InboxEnablement {
        KlaviyoInboxExtensionSDK.enablement(group: group ?? temp.group)
    }

    @Test
    func installedButNeverRegistered() {
        #expect(lookup() == .neverRegistered)
    }

    @Test(arguments: [
        (#"{"version":1,"enabled":true,"localRetentionLimit":25}"#, InboxEnablement.enabled(localRetentionLimit: 25)),
        (#"{"version":1,"enabled":false,"localRetentionLimit":25}"#, InboxEnablement.disabled),
        ("not json", InboxEnablement.disabled)
    ])
    func readsFixture(json: String, expected: InboxEnablement) throws {
        try writeFixture(json)
        #expect(lookup() == expected)
    }

    @Test
    func unavailableGroupIsReportedAsUnavailable() {
        for group in InboxTemporaryGroup.unavailable {
            #expect(lookup(group: group) == .unavailable)
        }
    }

    // MARK: Capture

    private func enable() throws {
        try InboxConfigStore(group: temp.group).enable(localRetentionLimit: 100)
    }

    func testCaptureHandsAnEnabledPushToTheSink() async throws {
        try enable()
        let sink = RecordingInboxCaptureSink()
        let capture = InboxCapture(group: temp.group, sink: sink)
        let result = await KlaviyoInboxExtensionSDK.capture(
            userInfo: InboxPayloadFixtures.userInfo(InboxPayloadFixtures.full),
            using: capture
        )
        XCTAssertEqual(result, .captured)
        XCTAssertEqual(sink.records.count, 1)
    }

    func testCaptureBeforeRegistrationDoesNothing() async {
        let sink = RecordingInboxCaptureSink()
        let capture = InboxCapture(group: temp.group, sink: sink)
        let result = await KlaviyoInboxExtensionSDK.capture(
            userInfo: InboxPayloadFixtures.userInfo(InboxPayloadFixtures.full),
            using: capture
        )
        XCTAssertEqual(result, .skipped)
        XCTAssertTrue(sink.records.isEmpty)
    }

    func testPublicCaptureNeverCrashesWithoutAnAppGroup() async {
        // The test host has no `klaviyo_app_group` entry, so this must skip quietly.
        await KlaviyoInboxExtensionSDK.capture(
            userInfo: InboxPayloadFixtures.userInfo(InboxPayloadFixtures.full)
        )
    }
}
#endif
