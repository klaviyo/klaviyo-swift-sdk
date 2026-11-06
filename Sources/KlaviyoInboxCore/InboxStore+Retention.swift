//
//  InboxStore+Retention.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import CoreData
import Foundation

extension InboxStore {
    /// Removes the company's messages beyond the newest `limit`, ordered by `sortTime` then `transmissionID`
    /// (the same order Android uses). Archived messages count toward the limit. Runs inside the capture
    /// transaction path. The expired rows are found by object ID, then removed
    /// SQL-side with a batch delete so no record is loaded into the extension's memory.
    static func trim(companyID: String, keeping limit: Int, in context: NSManagedObjectContext) throws {
        typealias Key = InboxStoreModel.Key
        let request = NSFetchRequest<NSManagedObjectID>(entityName: InboxStoreModel.entityName)
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(format: "%K == %@", Key.companyID, companyID)
        request.sortDescriptors = [
            NSSortDescriptor(key: Key.sortTime, ascending: false),
            NSSortDescriptor(key: Key.transmissionID, ascending: false)
        ]
        request.fetchOffset = max(limit, 0)
        let expired = try context.fetch(request)
        guard !expired.isEmpty else { return }

        let delete = NSBatchDeleteRequest(objectIDs: expired)
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
