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
    func unavailableGroupIsTreatedAsNeverRegistered() {
        for group in InboxTemporaryGroup.unavailable {
            #expect(lookup(group: group) == .neverRegistered)
        }
    }
}
#endif
