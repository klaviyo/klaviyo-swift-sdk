//
//  InboxConfigStoreTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class InboxConfigStoreTests: XCTestCase {
    private let groupId = "group.com.example.app"
    private var temp: InboxTemporaryGroup!
    private var logs: InboxLogRecorder!

    override func setUp() {
        super.setUp()
        temp = InboxTemporaryGroup()
        logs = InboxLogRecorder()
    }

    override func tearDown() {
        temp.remove()
        logs = nil
        temp = nil
        super.tearDown()
    }

    private func makeStore(group: InboxAppGroup? = nil) -> InboxConfigStore {
        InboxConfigStore(appGroupIdentifier: groupId, group: group ?? temp.group)
    }

    private func writeRaw(_ contents: String) throws {
        let store = makeStore()
        let directory = try XCTUnwrap(store.directoryURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: XCTUnwrap(store.fileURL))
    }

    func testNeverRegisteredWhenNothingWritten() {
        XCTAssertEqual(makeStore().enablement(), .neverRegistered)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: temp.root.path),
            "reading must not create anything"
        )
        XCTAssertTrue(logs.errors.isEmpty)
    }

    func testEnableThenReadFromSecondInstance() throws {
        try makeStore().enable(localRetentionLimit: 42)
        XCTAssertEqual(makeStore().enablement(), .enabled(localRetentionLimit: 42))
    }

    func testDisableAfterEnableKeepsFileAndRetention() throws {
        let store = makeStore()
        try store.enable(localRetentionLimit: 42)
        try store.disable()
        XCTAssertEqual(makeStore().enablement(), .disabled)
        let data = try Data(contentsOf: XCTUnwrap(store.fileURL))
        let record = try JSONDecoder().decode(InboxConfigRecord.self, from: data)
        XCTAssertEqual(record, InboxConfigRecord(enabled: false, localRetentionLimit: 42))
    }

    func testDisableWithoutPriorRecordIsDisabledNotNeverRegistered() throws {
        try makeStore().disable()
        XCTAssertEqual(makeStore().enablement(), .disabled)
    }

    func testEnableClampsOutOfRangeLimit() throws {
        let store = makeStore()
        try store.enable(localRetentionLimit: 0)
        XCTAssertEqual(store.enablement(), .enabled(localRetentionLimit: 1))
        try store.enable(localRetentionLimit: 9999)
        XCTAssertEqual(store.enablement(), .enabled(localRetentionLimit: 500))
    }

    func testReadClampsHandWrittenOutOfRangeLimit() throws {
        try writeRaw(#"{"version":1,"enabled":true,"localRetentionLimit":9999}"#)
        XCTAssertEqual(makeStore().enablement(), .enabled(localRetentionLimit: 500))
    }

    func testStoresFileInsideInboxDirectoryOfTheGroup() throws {
        let store = makeStore()
        try store.enable(localRetentionLimit: 10)
        let expected = temp.root
            .appendingPathComponent(groupId, isDirectory: true)
            .appendingPathComponent("KlaviyoInbox", isDirectory: true)
            .appendingPathComponent("klaviyo-inbox-config.json")
        XCTAssertEqual(store.fileURL?.standardizedFileURL, expected.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    }

    func testCorruptFileReadsAsNeverRegisteredAndIsKept() throws {
        try writeRaw("{ this is not json")
        let store = makeStore()
        XCTAssertEqual(store.enablement(), .neverRegistered)
        XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(store.fileURL).path))
        XCTAssertFalse(logs.errors.isEmpty)
    }

    func testNewerVersionReadsAsNeverRegisteredAndIsKept() throws {
        try writeRaw(#"{"version":999,"enabled":true,"localRetentionLimit":10}"#)
        let store = makeStore()
        XCTAssertEqual(store.enablement(), .neverRegistered)
        XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(store.fileURL).path))
        XCTAssertFalse(logs.errors.isEmpty)
    }

    func testVersionBelowOneReadsAsNeverRegisteredAndIsKept() throws {
        for version in [0, -1] {
            try writeRaw(#"{"version":\#(version),"enabled":true,"localRetentionLimit":10}"#)
            let store = makeStore()
            XCTAssertEqual(store.enablement(), .neverRegistered, "version \(version)")
            XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(store.fileURL).path))
        }
        XCTAssertFalse(logs.errors.isEmpty)
    }

    func testRegisterRepairsCorruptFile() throws {
        try writeRaw("garbage")
        let store = makeStore()
        try store.enable(localRetentionLimit: 7)
        XCTAssertEqual(store.enablement(), .enabled(localRetentionLimit: 7))
    }

    func testUnreachableGroupReadsAsNeverRegisteredAndLogs() {
        let store = makeStore(group: InboxTemporaryGroup.unreachable)
        XCTAssertEqual(store.enablement(), .neverRegistered)
        XCTAssertFalse(logs.errors.isEmpty)
    }

    func testUnreachableGroupWritesThrowGroupUnavailable() {
        let store = makeStore(group: InboxTemporaryGroup.unreachable)
        XCTAssertThrowsError(try store.enable(localRetentionLimit: 10)) {
            XCTAssertEqual($0 as? InboxConfigError, .groupUnavailable)
        }
        XCTAssertThrowsError(try store.disable()) {
            XCTAssertEqual($0 as? InboxConfigError, .groupUnavailable)
        }
    }

    func testEmptyIdentifierIsUnavailableAndTouchesNothing() {
        for identifier in ["", "   "] {
            let store = InboxConfigStore(appGroupIdentifier: identifier, group: temp.group)
            XCTAssertEqual(store.enablement(), .neverRegistered)
            XCTAssertThrowsError(try store.enable(localRetentionLimit: 10)) {
                XCTAssertEqual($0 as? InboxConfigError, .groupUnavailable)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.root.path))
    }

    func testWriteFailureThrowsWriteFailed() throws {
        // A regular file where the "KlaviyoInbox" directory should be makes createDirectory fail.
        let groupDirectory = temp.root.appendingPathComponent(groupId, isDirectory: true)
        try FileManager.default.createDirectory(at: groupDirectory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: groupDirectory.appendingPathComponent("KlaviyoInbox"))
        XCTAssertThrowsError(try makeStore().enable(localRetentionLimit: 10)) {
            XCTAssertEqual($0 as? InboxConfigError, .writeFailed)
        }
    }

    func testConcurrentReadsNeverSeeAPartialRecord() throws {
        let writer = makeStore()
        try writer.enable(localRetentionLimit: 10)
        let allowed: Set<String> = ["enabled10", "enabled20", "disabled"]
        let lock = NSLock()
        var unexpected: [InboxEnablement] = []

        DispatchQueue.concurrentPerform(iterations: 400) { index in
            if index % 4 == 0 {
                try? writer.enable(localRetentionLimit: index % 8 == 0 ? 10 : 20)
            } else if index % 4 == 1 {
                try? writer.disable()
            } else {
                let state = self.makeStore().enablement()
                let label: String
                switch state {
                case .enabled(10): label = "enabled10"
                case .enabled(20): label = "enabled20"
                case .disabled: label = "disabled"
                default: label = "other"
                }
                if !allowed.contains(label) {
                    lock.lock()
                    unexpected.append(state)
                    lock.unlock()
                }
            }
        }

        XCTAssertTrue(unexpected.isEmpty, "unexpected states: \(unexpected)")
        XCTAssertTrue(logs.errors.isEmpty, "a partial write would log a decode error: \(logs.errors)")
    }
}
