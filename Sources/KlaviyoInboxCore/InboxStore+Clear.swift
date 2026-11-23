//
//  InboxStore+Clear.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import CoreData
import Foundation

extension InboxStore {
    package func clear(companyID: String) async throws {
        let removed = try await perform { context in
            defer { context.reset() }
            let predicate = NSPredicate(format: "%K == %@", InboxStoreModel.Key.companyID, companyID)
            return try Self.batchDelete(matching: predicate, in: context)
        }
        if removed > 0 { changeSignal.post() }
    }

    /// Removes the company's messages with these ids and returns how many existed. Ids the company does
    /// not have, including another company's, are ignored.
    @discardableResult
    package func clear(ids: [String], companyID: String) async throws -> Int {
        guard !ids.isEmpty else { return 0 }
        let removed = try await perform { context in
            defer { context.reset() }
            let predicate = NSPredicate(
                format: "%K == %@ AND %K IN %@",
                InboxStoreModel.Key.companyID, companyID,
                InboxStoreModel.Key.transmissionID, ids
            )
            return try Self.batchDelete(matching: predicate, in: context)
        }
        if removed > 0 { changeSignal.post() }
        return removed
    }

    package func clearAll() async throws {
        let removed = try await perform { context in
            defer { context.reset() }
            return try Self.batchDelete(matching: nil, in: context)
        }
        if removed > 0 { changeSignal.post() }
    }

    /// Returns how many rows were removed.
    private static func batchDelete(
        matching predicate: NSPredicate?,
        in context: NSManagedObjectContext
    ) throws -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: InboxStoreModel.entityName)
        request.predicate = predicate
        let delete = NSBatchDeleteRequest(fetchRequest: request)
        delete.resultType = .resultTypeObjectIDs
        let result = try context.execute(delete) as? NSBatchDeleteResult
        guard let deleted = result?.result as? [NSManagedObjectID] else { return 0 }
        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSDeletedObjectsKey: deleted],
            into: [context]
        )
        return deleted.count
    }
}
