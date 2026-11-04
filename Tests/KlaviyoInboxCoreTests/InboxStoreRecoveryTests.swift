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

    private func makeStore(
        group: InboxAppGroup? = nil,
        recorder: RecordingStoreDiagnostics = RecordingStoreDiagnostics()
    ) -> (InboxStore, RecordingStoreDiagnostics) {
        let store = InboxStore(appGroup: group ?? appGroup, diagnostics: recorder.record)
        return (store, recorder)
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

    /// Writes rows straight through Core Data under `model`, the way another build would have.
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
                    let entity = try #require(NSEntityDescription.entity(
                        forEntityName: InboxStoreModel.entityName,
                        in: context
                    ))
                    let object = NSManagedObject(entity: entity, insertInto: context)
                    object.setValue(company, forKey: Key.companyID)
                    object.setValue(tm, forKey: Key.transmissionID)
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

    @Test
    func missingAppGroupIdentifierFailsWithoutThrowing() async {
        let group = InboxAppGroup(identifier: { nil }, containerURL: { _ in URL(fileURLWithPath: "/tmp") })
        let (store, recorder) = makeStore(group: group)
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(result == .failed)
        #expect(recorder.hasDegraded)
    }

    @Test
    func unreachableContainerFailsWithoutThrowing() async {
        let group = InboxAppGroup(identifier: { "group.test" }, containerURL: { _ in nil })
        let (store, recorder) = makeStore(group: group)
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(result == .failed)
        #expect(recorder.hasDegraded)
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

    @Test
    func aRepeatedlyFailingStoreIsLeftAloneAtFirstThenRebuilt() throws {
        try writeStore(model: InboxStoreModel.current, transmissionIDs: ["tm-1"])
        let url = try storeURL()
        let diagnostics = RecordingStoreDiagnostics()
        let opener = InboxStoreOpener(diagnostics: diagnostics.record)
        let coordinator = FailingCoordinator(
            model: InboxStoreModel.current,
            failure: NSError(domain: NSSQLiteErrorDomain, code: 6922)
        )

        // One-off contention (another process still creating the file) must never cost the user a store.
        #expect(throws: (any Error).self) { try opener.open(coordinator, at: url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!diagnostics.hasRecovered)

        // The same failure after the store has kept failing means the file itself is the problem.
        #expect(throws: (any Error).self) { try opener.open(coordinator, at: url, rebuildTransientFailures: true) }
        #expect(!(FileManager.default.fileExists(atPath: url.path)))
        #expect(diagnostics.hasRecovered)
    }

    // MARK: - Diagnostics carry a code someone can act on

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
        let (store, recorder) = makeStore()
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(result == .captured)
        #expect(recorder.hasRecovered)
        let stored = try await store.message(id: "tm-1")
        #expect(stored != nil)
        let files = try sqliteFiles()
        #expect(files == [InboxStore.storeFileName])
    }

    @Test
    func aStoreFromADifferentModelIsRebuilt() async throws {
        try writeStore(model: newerModel(), transmissionIDs: ["tm-1"])
        let (store, recorder) = makeStore()
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        #expect(result == .captured)
        #expect(recorder.hasRecovered)
        let old = try await store.message(id: "tm-1")
        #expect(old == nil)
        let files = try sqliteFiles()
        #expect(files == [InboxStore.storeFileName])
    }

    // MARK: - Journal mode, protection, bounded waiting

    @Test
    func theStoreIsInWALMode() async throws {
        let (store, _) = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let url = try storeURL()
        #expect(journalMode(at: url) == "wal")
    }

    @Test(.disabled(if: runsOnSimulator, "The simulator does not report a file protection class."))
    func storeFilesAreReadableWhileTheDeviceIsLocked() async throws {
        let (store, _) = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let url = try storeURL()
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            let item = try FileManager.default.attributesOfItem(atPath: url.path + suffix)
            #expect(item[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication, "store file \(suffix.isEmpty ? "main" : suffix)")
        }
    }
}

#endif
