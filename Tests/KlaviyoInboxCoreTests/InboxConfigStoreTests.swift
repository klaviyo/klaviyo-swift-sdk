//
//  InboxConfigStoreTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport

#if canImport(Testing)
import Testing

final class InboxConfigStoreTests {
    private let groupId = InboxTemporaryGroup.identifier
    private let temp = InboxTemporaryGroup()

    deinit {
        temp.remove()
    }

    private func makeStore(group: InboxAppGroup? = nil) -> InboxConfigStore {
        InboxConfigStore(group: group ?? temp.group)
    }

    private func writeRaw(_ contents: String) throws {
        let store = makeStore()
        let directory = try #require(store.directoryURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: #require(store.fileURL))
    }

    @Test
    func neverRegisteredWhenNothingWritten() {
        #expect(makeStore().enablement() == .neverRegistered)
        #expect(!FileManager.default.fileExists(atPath: temp.root.path), "reading must not create anything")
    }

    @Test
    func enableThenReadFromSecondInstance() throws {
        try makeStore().enable(localRetentionLimit: 42)
        #expect(makeStore().enablement() == .enabled(localRetentionLimit: 42))
    }

    @Test
    func disableAfterEnableKeepsFileAndRetention() throws {
        let store = makeStore()
        try store.enable(localRetentionLimit: 42)
        try store.disable()
        #expect(makeStore().enablement() == .disabled)
        let data = try Data(contentsOf: #require(store.fileURL))
        let record = try JSONDecoder().decode(InboxConfigRecord.self, from: data)
        #expect(record == InboxConfigRecord(enabled: false, localRetentionLimit: 42))
    }

    @Test
    func disableWithoutPriorRecordIsDisabledNotNeverRegistered() throws {
        try makeStore().disable()
        #expect(makeStore().enablement() == .disabled)
    }

    @Test(arguments: [(0, 1), (-5, 1), (9999, 500)])
    func enableClampsOutOfRangeLimit(requested: Int, expected: Int) throws {
        let store = makeStore()
        try store.enable(localRetentionLimit: requested)
        #expect(store.enablement() == .enabled(localRetentionLimit: expected))
    }

    @Test
    func readClampsHandWrittenOutOfRangeLimit() throws {
        try writeRaw(#"{"version":1,"enabled":true,"localRetentionLimit":9999}"#)
        #expect(makeStore().enablement() == .enabled(localRetentionLimit: 500))
    }

    @Test
    func storesFileInsideInboxDirectoryOfTheGroup() throws {
        let store = makeStore()
        try store.enable(localRetentionLimit: 10)
        let expected = temp.root
            .appendingPathComponent(groupId, isDirectory: true)
            .appendingPathComponent("KlaviyoInbox", isDirectory: true)
            .appendingPathComponent("klaviyo-inbox-config.json")
        #expect(store.fileURL?.standardizedFileURL == expected.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: expected.path))
    }

    /// Unusable files read as disabled (capture fails closed) and are left in place.
    @Test(arguments: [
        "{ this is not json",
        #"{"version":999,"enabled":true,"localRetentionLimit":10}"#,
        #"{"version":0,"enabled":true,"localRetentionLimit":10}"#,
        #"{"version":-1,"enabled":true,"localRetentionLimit":10}"#
    ])
    func unusableFileReadsAsDisabledAndIsKept(contents: String) throws {
        try writeRaw(contents)
        let store = makeStore()
        #expect(store.enablement() == .disabled)
        let fileURL = try #require(store.fileURL)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test
    func registerRepairsCorruptFile() throws {
        try writeRaw("garbage")
        let store = makeStore()
        try store.enable(localRetentionLimit: 7)
        #expect(store.enablement() == .enabled(localRetentionLimit: 7))
    }

    @Test
    func unreachableGroupReadsAsNeverRegistered() {
        #expect(makeStore(group: InboxTemporaryGroup.unreachable).enablement() == .neverRegistered)
    }

    @Test
    func unreachableGroupWritesThrowAppGroupUnavailable() {
        let store = makeStore(group: InboxTemporaryGroup.unreachable)
        #expect(throws: InboxConfigError.appGroupUnavailable) { try store.enable(localRetentionLimit: 10) }
        #expect(throws: InboxConfigError.appGroupUnavailable) { try store.disable() }
    }

    @Test(arguments: ["missing", "empty", "blank"])
    func missingOrBlankInfoPlistEntryIsUnavailableAndTouchesNothing(kind: String) {
        let containerURL = temp.group.containerURL
        let group: InboxAppGroup
        switch kind {
        case "missing": group = InboxTemporaryGroup.missingIdentifier
        case "empty": group = InboxAppGroup(identifier: { "" }, containerURL: containerURL)
        default: group = InboxAppGroup(identifier: { "   " }, containerURL: containerURL)
        }
        let store = makeStore(group: group)
        #expect(store.enablement() == .neverRegistered)
        #expect(throws: InboxConfigError.appGroupUnavailable) { try store.enable(localRetentionLimit: 10) }
        #expect(!FileManager.default.fileExists(atPath: temp.root.path))
    }

    @Test
    func writeFailureThrowsWriteFailed() throws {
        // A regular file where the "KlaviyoInbox" directory should be makes createDirectory fail.
        let groupDirectory = temp.root.appendingPathComponent(groupId, isDirectory: true)
        try FileManager.default.createDirectory(at: groupDirectory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: groupDirectory.appendingPathComponent("KlaviyoInbox"))
        let store = makeStore()
        #expect(throws: InboxConfigError.writeFailed) { try store.enable(localRetentionLimit: 10) }
    }

    @Test
    func concurrentReadsNeverSeeAPartialRecord() throws {
        let writer = makeStore()
        try writer.enable(localRetentionLimit: 10)
        let fileURL = try #require(writer.fileURL)
        let lock = NSLock()
        var undecodable = 0

        DispatchQueue.concurrentPerform(iterations: 400) { index in
            switch index % 4 {
            case 0: try? writer.enable(localRetentionLimit: index % 8 == 0 ? 10 : 20)
            case 1: try? writer.disable()
            default:
                // Decode the raw file: `enablement()` would mask a torn write as `.disabled`.
                let decoded = (try? Data(contentsOf: fileURL))
                    .flatMap { try? JSONDecoder().decode(InboxConfigRecord.self, from: $0) }
                if decoded == nil {
                    lock.lock()
                    undecodable += 1
                    lock.unlock()
                }
            }
        }

        #expect(undecodable == 0, "atomic writes must never expose a partial record")
    }
}
#endif
