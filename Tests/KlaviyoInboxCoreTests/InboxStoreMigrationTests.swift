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
        let dropped: Set<String> = [InboxStoreModel.Key.readUpdatedAt, InboxStoreModel.Key.archivedUpdatedAt]
        entity.properties = entity.properties.filter { !dropped.contains($0.name) }
        return copy
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

    private func store(knowing previous: NSManagedObjectModel) -> InboxStore {
        InboxStore(appGroup: appGroup, changeSignal: RecordingInboxChangeSignal(), previousModels: [previous])
    }

    private func sqliteFiles() throws -> [String] {
        let directory = try #require(appGroup.inboxDirectory())
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".sqlite") }
            .sorted()
    }

    @Test
    func aStoreFromAKnownEarlierModelIsMigratedWithItsMessages() async throws {
        let earlier = try earlierModel()
        try InboxStoreFixtures.writeStore(model: earlier, transmissionIDs: ["tm-1", "tm-2"], in: appGroup)
        let store = store(knowing: earlier)
        for id in ["tm-1", "tm-2"] {
            let message = try await store.message(id: id)
            #expect(message != nil, "\(id) survived")
            #expect(message?.readUpdatedAt == nil)
            #expect(message?.archivedUpdatedAt == nil)
            #expect(message?.isRead == false)
        }
        let changed = try await store.setRead(true, id: "tm-1", companyID: company)
        #expect(changed == .changed)
        let files = try sqliteFiles()
        #expect(files == [InboxStore.storeFileName])
    }

    @Test
    func aMigratedStoreKeepsWorkingForNewCaptures() async throws {
        let earlier = try earlierModel()
        try InboxStoreFixtures.writeStore(model: earlier, transmissionIDs: ["tm-1"], in: appGroup)
        let store = store(knowing: earlier)
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        #expect(result == .captured)
        let old = try await store.message(id: "tm-1")
        #expect(old != nil)
    }

    @Test
    func aStoreFromAnUnknownModelIsStillRebuiltWhenAnEarlierModelIsKnown() async throws {
        try InboxStoreFixtures.writeStore(model: newerModel(), transmissionIDs: ["tm-1"], in: appGroup)
        let store = try store(knowing: earlierModel())
        let result = await store.capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        #expect(result == .captured)
        let old = try await store.message(id: "tm-1")
        #expect(old == nil)
    }

    @Test
    func aStoreAlreadyOnTheCurrentModelIsNotMigrated() async throws {
        try InboxStoreFixtures.writeStore(model: InboxStoreModel.current, transmissionIDs: ["tm-1"], in: appGroup)
        let store = try store(knowing: earlierModel())
        let message = try await store.message(id: "tm-1")
        #expect(message != nil)
    }
}
#endif
