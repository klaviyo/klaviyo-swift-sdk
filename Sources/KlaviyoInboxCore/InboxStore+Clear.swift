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
        try await perform { context in
            defer { context.reset() }
            let predicate = NSPredicate(format: "%K == %@", InboxStoreModel.Key.companyID, companyID)
            try Self.batchDelete(matching: predicate, in: context)
        }
    }

    package func clearAll() async throws {
        try await perform { context in
            defer { context.reset() }
            try Self.batchDelete(matching: nil, in: context)
        }
    }

    private static func batchDelete(matching predicate: NSPredicate?, in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: InboxStoreModel.entityName)
        request.predicate = predicate
        let delete = NSBatchDeleteRequest(fetchRequest: request)
        delete.resultType = .resultTypeObjectIDs
        let result = try context.execute(delete) as? NSBatchDeleteResult
        if let deleted = result?.result as? [NSManagedObjectID] {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: deleted],
                into: [context]
            )
        }
    }
}
