//
//  InboxStoreRecoveryTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

@testable import KlaviyoInboxCore
import CoreData
import Foundation
import KlaviyoInboxTestSupport
import SQLite3
import XCTest

final class InboxStoreRecoveryTests: XCTestCase {
    private var appGroup: InboxAppGroup!
    private let company = InboxStoreFixtures.company
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        appGroup = InboxStoreFixtures.temporaryAppGroup()
    }

    // MARK: - Helpers

    private func makeStore(
        group: InboxAppGroup? = nil,
        history: [NSManagedObjectModel] = InboxStoreModel.history,
        now: @escaping () -> Date = Date.init,
        recorder: RecordingStoreDiagnostics = RecordingStoreDiagnostics()
    ) -> (InboxStore, RecordingStoreDiagnostics) {
        let store = InboxStore(
            appGroup: group ?? appGroup,
            now: now,
            diagnostics: recorder.record,
            modelHistory: history
        )
        return (store, recorder)
    }

    private func storeURL() throws -> URL {
        try XCTUnwrap(appGroup.inboxDirectory()).appendingPathComponent(InboxStore.storeFileName)
    }

    private func quarantined() throws -> [String] {
        let directory = try XCTUnwrap(appGroup.inboxDirectory())
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains("quarantine") && $0.hasSuffix(".sqlite") }
            .sorted()
    }

    private func writeGarbage(over url: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
        try Data("this is not a sqlite database".utf8).write(to: url)
    }

    private func model(removing name: String? = nil, adding extra: String? = nil) throws -> NSManagedObjectModel {
        let copy = try XCTUnwrap(InboxStoreModel.current.copy() as? NSManagedObjectModel)
        let entity = try XCTUnwrap(copy.entitiesByName[InboxStoreModel.entityName])
        var properties = entity.properties
        if let name { properties.removeAll { $0.name == name } }
        if let extra {
            let attribute = NSAttributeDescription()
            attribute.name = extra
            attribute.attributeType = .stringAttributeType
            attribute.isOptional = true
            properties.append(attribute)
        }
        entity.properties = properties
        return copy
    }

    /// Writes rows straight through Core Data under `model`, the way an older or newer build would have.
    private func writeStore(model: NSManagedObjectModel, transmissionIDs: [String]) throws {
        typealias Key = InboxStoreModel.Key
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL(),
            options: nil
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        var failure: Error?
        context.performAndWait {
            do {
                for tm in transmissionIDs {
                    let record = InboxStoreFixtures.record(tm: tm, sentAt: epoch)
                    let entity = try XCTUnwrap(NSEntityDescription.entity(
                        forEntityName: InboxStoreModel.entityName,
                        in: context
                    ))
                    let object = NSManagedObject(entity: entity, insertInto: context)
                    object.setValue(company, forKey: Key.companyID)
                    object.setValue(tm, forKey: Key.transmissionID)
                    object.setValue(epoch, forKey: Key.receivedAt)
                    object.setValue(epoch, forKey: Key.sortTime)
                    try object.setValue(JSONEncoder().encode(record), forKey: Key.payload)
                }
                try context.save()
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        try coordinator.remove(store)
    }

    private func journalMode(at url: URL) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA journal_mode;", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: text)
    }

    // MARK: - Unreachable App Group

    func testMissingAppGroupIdentifierFailsWithoutThrowing() async {
        let group = InboxAppGroup(identifier: { nil }, containerURL: { _ in URL(fileURLWithPath: "/tmp") })
        let (store, recorder) = makeStore(group: group)
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        XCTAssertEqual(result, .failed)
        XCTAssertTrue(recorder.hasDegraded)
    }

    func testUnreachableContainerFailsWithoutThrowing() async {
        let group = InboxAppGroup(identifier: { "group.test" }, containerURL: { _ in nil })
        let (store, recorder) = makeStore(group: group)
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        XCTAssertEqual(result, .failed)
        XCTAssertTrue(recorder.hasDegraded)
    }

    // MARK: - Transient failures must never cost the user their messages

    func testOnlyLockResourceAndIOErrorsAreTransient() {
        func sqlite(_ code: Int) -> Error { NSError(domain: NSSQLiteErrorDomain, code: code) }
        XCTAssertTrue(InboxStoreError.isTransient(sqlite(5)))
        XCTAssertTrue(InboxStoreError.isTransient(sqlite(6)))
        XCTAssertTrue(InboxStoreError.isTransient(sqlite(13)))
        // Disk I/O errors, including extended codes such as 6922 (a file moved under an open connection),
        // say nothing about the file's content.
        XCTAssertTrue(InboxStoreError.isTransient(sqlite(10)))
        XCTAssertTrue(InboxStoreError.isTransient(sqlite(6922)))
        // Corruption and "not a database" are the cases that do justify quarantine.
        XCTAssertFalse(InboxStoreError.isTransient(sqlite(11)))
        XCTAssertFalse(InboxStoreError.isTransient(sqlite(26)))
        XCTAssertFalse(InboxStoreError.isTransient(NSError(domain: NSCocoaErrorDomain, code: 134_030)))
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_030,
            userInfo: [NSUnderlyingErrorKey: sqlite(5)]
        )
        XCTAssertTrue(InboxStoreError.isTransient(wrapped))
    }

    // MARK: - A store that keeps failing to open must eventually be rebuilt

    /// A coordinator whose store can never be added, standing in for a file that keeps returning a disk
    /// I/O error.
    private final class FailingCoordinator: NSPersistentStoreCoordinator {
        let failure: Error

        init(model: NSManagedObjectModel, failure: Error) {
            self.failure = failure
            super.init(managedObjectModel: model)
        }

        override func addPersistentStore(
            ofType storeType: String,
            configurationName configuration: String?,
            at storeURL: URL?,
            options: [AnyHashable: Any]? = nil
        ) throws -> NSPersistentStore {
            throw failure
        }
    }

    func testARepeatedlyFailingStoreIsLeftAloneAtFirstThenQuarantined() throws {
        try writeStore(model: InboxStoreModel.current, transmissionIDs: ["tm-1"])
        let url = try storeURL()
        let diagnostics = RecordingStoreDiagnostics()
        let opener = InboxStoreOpener(
            modelHistory: InboxStoreModel.history,
            now: { self.epoch },
            diagnostics: diagnostics.record
        )
        let coordinator = FailingCoordinator(
            model: InboxStoreModel.current,
            failure: NSError(domain: NSSQLiteErrorDomain, code: 6922)
        )

        // One-off contention (another process still creating the file) must never cost the user a store.
        XCTAssertThrowsError(try opener.open(coordinator, at: url))
        XCTAssertTrue(try quarantined().isEmpty)
        XCTAssertFalse(diagnostics.hasRecovered)

        // The same failure after the store has kept failing means the file itself is the problem.
        XCTAssertThrowsError(try opener.open(coordinator, at: url, quarantineTransientFailures: true))
        XCTAssertEqual(try quarantined().count, 1)
        XCTAssertTrue(diagnostics.hasRecovered)
    }

    // MARK: - Diagnostics carry a code someone can act on

    func testDiagnosticCodesNameTheSQLiteErrorWhereThereIsOne() {
        func sqlite(_ code: Int) -> NSError { NSError(domain: NSSQLiteErrorDomain, code: code) }
        XCTAssertEqual(InboxStoreError.diagnosticCode(for: sqlite(5)), 5)
        XCTAssertEqual(InboxStoreError.diagnosticCode(for: InboxStoreError.underlying(sqlite(6922))), 6922)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_030, userInfo: [NSUnderlyingErrorKey: sqlite(11)])
        XCTAssertEqual(InboxStoreError.diagnosticCode(for: wrapped), 11)
        XCTAssertEqual(InboxStoreError.diagnosticCode(for: InboxStoreError.underlying(wrapped)), 11)
    }

    func testDiagnosticCodesFallBackToTheErrorCodeAndNameAnUnavailableStore() {
        XCTAssertEqual(
            InboxStoreError.diagnosticCode(for: NSError(domain: NSCocoaErrorDomain, code: 512)),
            512
        )
        XCTAssertEqual(
            InboxStoreError.diagnosticCode(for: InboxStoreError.unavailable),
            InboxStoreError.unavailableCode
        )
        XCTAssertLessThan(InboxStoreError.unavailableCode, 0)
    }

    // MARK: - Corrupt store

    func testACorruptStoreIsQuarantinedAndCaptureWorksAfterwards() async throws {
        try writeGarbage(over: storeURL())
        let (store, recorder) = makeStore(now: { self.epoch })
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        XCTAssertEqual(result, .captured)
        XCTAssertTrue(recorder.hasRecovered)
        let stored = try await store.message(id: "tm-1")
        XCTAssertNotNil(stored)
        XCTAssertEqual(try quarantined().count, 1)
    }

    func testOnlyTheMostRecentQuarantineIsKept() async throws {
        var clock = epoch
        do {
            try writeGarbage(over: storeURL())
            let (store, _) = makeStore(now: { clock })
            _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        }
        clock = epoch.addingTimeInterval(60)
        try writeGarbage(over: storeURL())
        let (second, _) = makeStore(now: { clock })
        let result = await second.capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        XCTAssertEqual(result, .captured)
        let kept = try quarantined()
        XCTAssertEqual(kept.count, 1)
        XCTAssertTrue(kept[0].contains("\(Int(clock.timeIntervalSince1970))"))
    }

    // MARK: - Migration

    func testAnOlderModelMigratesWithItsRowsPreserved() async throws {
        let older = try model(removing: InboxStoreModel.Key.body)
        try writeStore(model: older, transmissionIDs: ["tm-1", "tm-2"])
        let (store, recorder) = makeStore(history: [older, InboxStoreModel.current])
        let first = try await store.message(id: "tm-1")
        let second = try await store.message(id: "tm-2")
        XCTAssertEqual(first?.record.attribution.transmissionID, "tm-1")
        XCTAssertEqual(second?.record.attribution.transmissionID, "tm-2")
        XCTAssertTrue(recorder.events.contains(.migrated(from: 1, to: 2)))
        XCTAssertFalse(recorder.hasRecovered)
        XCTAssertTrue(try quarantined().isEmpty)
    }

    func testAMigratedStoreStillTakesNewCaptures() async throws {
        let older = try model(removing: InboxStoreModel.Key.body)
        try writeStore(model: older, transmissionIDs: ["tm-1"])
        let (store, _) = makeStore(history: [older, InboxStoreModel.current])
        let replay = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let fresh = await store.capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        XCTAssertEqual(replay, .duplicate)
        XCTAssertEqual(fresh, .captured)
    }

    func testAStoreFromANewerModelIsQuarantined() async throws {
        let newer = try model(adding: "futureField")
        try writeStore(model: newer, transmissionIDs: ["tm-1"])
        let (store, recorder) = makeStore(now: { self.epoch })
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        XCTAssertEqual(result, .captured)
        XCTAssertTrue(recorder.hasRecovered)
        let old = try await store.message(id: "tm-1")
        XCTAssertNil(old)
        XCTAssertEqual(try quarantined().count, 1)
    }

    // MARK: - Journal mode, protection, bounded waiting

    func testTheStoreIsInWALMode() async throws {
        let (store, _) = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        XCTAssertEqual(try journalMode(at: storeURL()), "wal")
    }

    func testStoreFilesAreReadableWhileTheDeviceIsLocked() async throws {
        let (store, _) = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let url = try storeURL()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = attributes[.protectionKey] as? FileProtectionType
        try XCTSkipIf(protection == nil, "This platform does not report a file protection class.")
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            let item = try FileManager.default.attributesOfItem(atPath: url.path + suffix)
            XCTAssertEqual(
                item[.protectionKey] as? FileProtectionType,
                .completeUntilFirstUserAuthentication,
                "store file \(suffix.isEmpty ? "main" : suffix)"
            )
        }
    }
}
