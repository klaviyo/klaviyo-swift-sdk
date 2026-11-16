//
//  InboxStoreMigrationTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/13/26.
//

@testable import KlaviyoInboxCore
import CoreData
import Foundation
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxStoreMigrationTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    /// The current model without the updated-at attributes, standing in for an earlier build's model.
    private func earlierModel() throws -> NSManagedObjectModel {
        let copy = try #require(InboxStoreModel.current.copy() as? NSManagedObjectModel)
        let entity = try #require(copy.entitiesByName[InboxStoreModel.entityName])
        let dropped: Set<String> = [
            InboxStoreModel.Key.readUpdatedAt,
            InboxStoreModel.Key.archivedUpdatedAt,
            InboxStoreModel.Key.updatedAt,
            InboxStoreModel.Key.expiresAt
        ]
        entity.properties = entity.properties.filter { !dropped.contains($0.name) }
        return copy
    }

    /// The current model with `updatedAt` as a string, which Core Data cannot infer a mapping to a date from.
    private func uninferableEarlierModel() throws -> NSManagedObjectModel {
        let copy = try #require(InboxStoreModel.current.copy() as? NSManagedObjectModel)
        let entity = try #require(copy.entitiesByName[InboxStoreModel.entityName])
        let updatedAt = try #require(entity.propertiesByName[InboxStoreModel.Key.updatedAt] as? NSAttributeDescription)
        updatedAt.attributeType = .stringAttributeType
        return copy
    }

    private func currentStore() -> InboxStore {
        InboxStore(appGroup: appGroup, changeSignal: RecordingInboxChangeSignal())
    }

    private func sqliteFiles() throws -> [String] {
        let directory = try #require(appGroup.inboxDirectory())
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".sqlite") }
            .sorted()
    }

    @Test
    func aStoreFromAnEarlierModelIsMigratedWithItsMessages() async throws {
        try InboxStoreFixtures.writeStore(model: earlierModel(), transmissionIDs: ["tm-1", "tm-2"], in: appGroup)
        let store = currentStore()
        for id in ["tm-1", "tm-2"] {
            let message = try await store.message(id: id)
            #expect(message != nil, "\(id) survived")
            #expect(message?.readUpdatedAt == nil)
            #expect(message?.archivedUpdatedAt == nil)
            #expect(message?.updatedAt == nil)
            #expect(message?.expiresAt == nil)
            #expect(message?.isRead == false)
        }
        let changed = try await store.setRead(true, id: "tm-1", companyID: company)
        #expect(changed == .changed)
        let files = try sqliteFiles()
        #expect(files == [InboxStore.storeFileName])
    }

    @Test
    func aMigratedStoreKeepsWorkingForNewCaptures() async throws {
        try InboxStoreFixtures.writeStore(model: earlierModel(), transmissionIDs: ["tm-1"], in: appGroup)
        let store = currentStore()
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        #expect(result == .captured)
        let old = try await store.message(id: "tm-1")
        #expect(old != nil)
    }

    /// A change Core Data cannot infer says nothing about the file, so it fails the open and the messages
    /// stay for a build that can read them, instead of being rebuilt away.
    @Test
    func aChangeCoreDataCannotInferFailsTheOpenAndKeepsTheStore() async throws {
        let earlier = try uninferableEarlierModel()
        try InboxStoreFixtures.writeStore(model: earlier, transmissionIDs: ["tm-1"], in: appGroup)
        let result = await currentStore().capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        #expect(result == .failed)
        let directory = try #require(appGroup.inboxDirectory())
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: directory.appendingPathComponent(InboxStore.storeFileName),
            options: nil
        )
        #expect(earlier.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))
    }

    @Test
    func aStoreAlreadyOnTheCurrentModelIsOpenedAsIs() async throws {
        try InboxStoreFixtures.writeStore(model: InboxStoreModel.current, transmissionIDs: ["tm-1"], in: appGroup)
        let message = try await currentStore().message(id: "tm-1")
        #expect(message != nil)
    }
}
#endif
