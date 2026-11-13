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
#if canImport(Testing)
import Testing

#if targetEnvironment(simulator)
private let runsOnSimulator = true
#else
private let runsOnSimulator = false
#endif

@Suite
struct InboxStoreRecoveryTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Helpers

    private func makeStore(group: InboxAppGroup? = nil) -> InboxStore {
        InboxStoreFixtures.store(appGroup: group ?? appGroup)
    }

    private func storeURL() throws -> URL {
        try #require(appGroup.inboxDirectory()).appendingPathComponent(InboxStore.storeFileName)
    }

    /// Every SQLite file in the Inbox directory. A rebuild leaves only the live store, never a copy of
    /// the bad one.
    private func sqliteFiles() throws -> [String] {
        let directory = try #require(appGroup.inboxDirectory())
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".sqlite") }
            .sorted()
    }

    private func writeGarbage(over url: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
        try Data("this is not a sqlite database".utf8).write(to: url)
    }

    /// The current model plus one more attribute, standing in for a newer build's model.
    private func newerModel() throws -> NSManagedObjectModel {
        let copy = try #require(InboxStoreModel.current.copy() as? NSManagedObjectModel)
        let entity = try #require(copy.entitiesByName[InboxStoreModel.entityName])
        let attribute = NSAttributeDescription()
        attribute.name = "futureField"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = true
        entity.properties += [attribute]
        return copy
    }

    private func writeStore(model: NSManagedObjectModel, transmissionIDs: [String]) throws {
        try InboxStoreFixtures.writeStore(model: model, transmissionIDs: transmissionIDs, in: appGroup)
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

    @Test
    func missingAppGroupIdentifierFailsWithoutThrowing() async {
        let group = InboxAppGroup(identifier: { nil }, containerURL: { _ in URL(fileURLWithPath: "/tmp") })
        let store = makeStore(group: group)
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(result == .failed)
    }

    @Test
    func unreachableContainerFailsWithoutThrowing() async {
        let group = InboxAppGroup(identifier: { "group.test" }, containerURL: { _ in nil })
        let store = makeStore(group: group)
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(result == .failed)
    }

    // MARK: - Transient failures must never cost the user their messages

    @Test
    func onlyLockResourceAndIOErrorsAreTransient() {
        func sqlite(_ code: Int) -> Error { NSError(domain: NSSQLiteErrorDomain, code: code) }
        #expect(InboxStoreError.isTransient(sqlite(5)))
        #expect(InboxStoreError.isTransient(sqlite(6)))
        #expect(InboxStoreError.isTransient(sqlite(13)))
        // Disk I/O errors, including extended codes such as 6922 (a file moved under an open connection),
        // say nothing about the file's content.
        #expect(InboxStoreError.isTransient(sqlite(10)))
        #expect(InboxStoreError.isTransient(sqlite(6922)))
        // Corruption and "not a database" are the cases that do justify a rebuild.
        #expect(!InboxStoreError.isTransient(sqlite(11)))
        #expect(!InboxStoreError.isTransient(sqlite(26)))
        #expect(!(InboxStoreError.isTransient(NSError(domain: NSCocoaErrorDomain, code: 134_030))))
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_030,
            userInfo: [NSUnderlyingErrorKey: sqlite(5)]
        )
        #expect(InboxStoreError.isTransient(wrapped))
    }

    // MARK: - Only corruption justifies deleting the store

    @Test
    func onlyCorruptionAndIncompatibleModelsAreRebuilt() {
        func sqlite(_ code: Int) -> NSError { NSError(domain: NSSQLiteErrorDomain, code: code) }
        func cocoa(_ code: Int, underlying: NSError? = nil) -> NSError {
            NSError(
                domain: NSCocoaErrorDomain,
                code: code,
                userInfo: underlying.map { [NSUnderlyingErrorKey: $0] } ?? [:]
            )
        }
        #expect(InboxStoreError.indicatesCorruption(sqlite(11)))
        #expect(InboxStoreError.indicatesCorruption(sqlite(26)))
        #expect(InboxStoreError.indicatesCorruption(sqlite(267))) // SQLITE_CORRUPT_VTAB, an extended code
        #expect(InboxStoreError.indicatesCorruption(cocoa(134_100)))
        #expect(InboxStoreError.indicatesCorruption(cocoa(134_130)))
        #expect(InboxStoreError.indicatesCorruption(cocoa(134_030, underlying: sqlite(11))))
        #expect(InboxStoreError.indicatesCorruption(InboxStoreError.underlying(cocoa(134_100))))
        // Contention, resource pressure, I/O errors, and errors with no SQLite code say nothing about the file.
        for code in [5, 6, 7, 10, 13, 14, 6922] {
            #expect(!InboxStoreError.indicatesCorruption(sqlite(code)), "SQLite \(code)")
        }
        // A file that is not a database: Cocoa 259 with the SQLite code as a number in `userInfo`.
        let notADatabase = NSError(
            domain: NSCocoaErrorDomain,
            code: 259,
            userInfo: [NSSQLiteErrorDomain: NSNumber(value: 26)]
        )
        #expect(InboxStoreError.indicatesCorruption(notADatabase))
        #expect(InboxStoreError.diagnosticCode(for: notADatabase) == 26)
        #expect(!InboxStoreError.indicatesCorruption(cocoa(134_030)))
        #expect(!InboxStoreError.indicatesCorruption(InboxStoreError.unavailable))
    }

    // MARK: - A store that keeps failing to open is never deleted

    /// A coordinator whose store can never be added, standing in for a file that keeps failing to open.
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

    @Test(arguments: [5, 6, 13, 6922])
    func aStoreThatKeepsFailingToOpenKeepsItsMessages(code: Int) async throws {
        let ids = ["tm-1", "tm-2"]
        try writeStore(model: InboxStoreModel.current, transmissionIDs: ids)
        let url = try storeURL()
        let opener = InboxStoreOpener()
        let coordinator = FailingCoordinator(
            model: InboxStoreModel.current,
            failure: NSError(domain: NSSQLiteErrorDomain, code: code)
        )

        for _ in 0..<3 {
            #expect(throws: (any Error).self) { try opener.open(coordinator, at: url) }
        }
        #expect(FileManager.default.fileExists(atPath: url.path))

        let store = makeStore()
        for id in ids {
            let stored = try await store.message(id: id)
            #expect(stored != nil, "\(id) survived")
        }
    }

    @Test
    func aStoreThatFailsWithoutASQLiteCodeIsNotRebuilt() async throws {
        try writeStore(model: InboxStoreModel.current, transmissionIDs: ["tm-1"])
        let url = try storeURL()
        let coordinator = FailingCoordinator(
            model: InboxStoreModel.current,
            failure: NSError(domain: NSCocoaErrorDomain, code: 134_030)
        )
        #expect(throws: (any Error).self) { try InboxStoreOpener().open(coordinator, at: url) }
        let store = makeStore()
        let stored = try await store.message(id: "tm-1")
        #expect(stored != nil)
    }

    // MARK: - No rebuild without the open lock

    @Test
    func aCorruptStoreIsLeftAloneWhileAnotherProcessHoldsTheOpenLock() async throws {
        let url = try storeURL()
        try writeGarbage(over: url)
        let garbage = try Data(contentsOf: url)
        let lockPath = url.deletingLastPathComponent().appendingPathComponent("klaviyo-inbox.lock").path
        let descriptor = Darwin.open(lockPath, O_CREAT | O_RDWR, 0o600)
        try #require(descriptor >= 0)
        defer { Darwin.close(descriptor) }
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)

        let store = makeStore()
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(result == .failed)
        let afterwards = try Data(contentsOf: url)
        #expect(afterwards == garbage)

        // Once the lock is free, the next capture does the rebuild.
        flock(descriptor, LOCK_UN)
        let retry = makeStore()
        let retried = await retry.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(retried == .captured)
    }

    // MARK: - Log lines carry a code someone can act on

    @Test
    func diagnosticCodesNameTheSQLiteErrorWhereThereIsOne() {
        func sqlite(_ code: Int) -> NSError { NSError(domain: NSSQLiteErrorDomain, code: code) }
        #expect(InboxStoreError.diagnosticCode(for: sqlite(5)) == 5)
        #expect(InboxStoreError.diagnosticCode(for: InboxStoreError.underlying(sqlite(6922))) == 6922)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_030, userInfo: [NSUnderlyingErrorKey: sqlite(11)])
        #expect(InboxStoreError.diagnosticCode(for: wrapped) == 11)
        #expect(InboxStoreError.diagnosticCode(for: InboxStoreError.underlying(wrapped)) == 11)
    }

    @Test
    func diagnosticCodesFallBackToTheErrorCodeAndNameAnUnavailableStore() {
        #expect(InboxStoreError.diagnosticCode(for: NSError(domain: NSCocoaErrorDomain, code: 512)) == 512)
        #expect(InboxStoreError.diagnosticCode(for: InboxStoreError.unavailable) == InboxStoreError.unavailableCode)
        #expect(InboxStoreError.unavailableCode < 0)
    }

    // MARK: - Corrupt or foreign store

    @Test
    func aCorruptStoreIsRebuiltAndCaptureWorksAfterwards() async throws {
        try writeGarbage(over: storeURL())
        let store = makeStore()
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(result == .captured)
        let stored = try await store.message(id: "tm-1")
        #expect(stored != nil)
        let files = try sqliteFiles()
        #expect(files == [InboxStore.storeFileName])
    }

    @Test
    func aStoreFromADifferentModelIsRebuilt() async throws {
        try writeStore(model: newerModel(), transmissionIDs: ["tm-1"])
        let store = makeStore()
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        #expect(result == .captured)
        let old = try await store.message(id: "tm-1")
        #expect(old == nil)
        let files = try sqliteFiles()
        #expect(files == [InboxStore.storeFileName])
    }

    // MARK: - Journal mode, protection, bounded waiting

    @Test
    func theStoreIsInWALMode() async throws {
        let store = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let url = try storeURL()
        #expect(journalMode(at: url) == "wal")
    }

    @Test(.disabled(if: runsOnSimulator, "The simulator does not report a file protection class."))
    func storeFilesAreReadableWhileTheDeviceIsLocked() async throws {
        let store = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let url = try storeURL()
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            let item = try FileManager.default.attributesOfItem(atPath: url.path + suffix)
            #expect(item[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication, "store file \(suffix.isEmpty ? "main" : suffix)")
        }
    }
}

#endif
