//
//  InboxStore+Clear.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import CoreData
import Foundation

extension InboxStore {
    /// Removes every message for one company and returns how many were removed. Other companies' messages
    /// are left alone. This is a row delete, never a store teardown: the store file is shared with the
    /// Notification Service Extension. Posts the change signal once, and only when a row was removed.
    ///
    /// Not the profile-reset clear: that is ``clearAll()``, which empties every company.
    @discardableResult
    package func clear(companyID: String) async throws -> Int {
        let removed = try await perform { context in
            defer { context.reset() }
            let predicate = NSPredicate(format: "%K == %@", InboxStoreModel.Key.companyID, companyID)
            return try Self.batchDelete(matching: predicate, in: context)
        }
        if removed > 0 { changeSignal.post() }
        return removed
    }

    /// Removes every message for every company. This is the profile-reset clear; the public
    /// ``MobileInbox`` `clearAll()` is current-company only and uses ``clear(companyID:)``.
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
