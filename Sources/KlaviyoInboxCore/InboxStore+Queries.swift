//
//  InboxStore+Queries.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import CoreData
import Foundation

extension InboxStore: InboxStoring {
    package func fetch(_ query: InboxStoreQuery) async throws -> InboxStorePage {
        try await perform { context in
            defer { context.reset() }
            typealias Key = InboxStoreModel.Key
            let limit = max(query.limit, 0)
            let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
            request.predicate = Self.predicate(for: query)
            request.sortDescriptors = [
                NSSortDescriptor(key: Key.sortTime, ascending: false),
                NSSortDescriptor(key: Key.transmissionID, ascending: false)
            ]
            // One extra row tells us whether another page exists without a second query.
            request.fetchLimit = limit + 1
            let rows = try context.fetch(request)
            let messages = try rows.prefix(limit).map(Self.stored)
            let nextCursor = rows.count > limit ? messages.last.map { last in
                InboxStoreCursor(sortTime: last.record.sentAt ?? last.record.receivedAt, id: last.id)
            } : nil
            return InboxStorePage(messages: messages, nextCursor: nextCursor)
        }
    }

    package func setState(_ state: InboxLocalState, companyID: String, ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await perform { context in
            defer { context.reset() }
            typealias Key = InboxStoreModel.Key
            let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
            request.predicate = NSPredicate(
                format: "%K == %@ AND %K IN %@",
                Key.companyID, companyID,
                Key.transmissionID, ids
            )
            let (key, value): (String, Bool) = {
                switch state {
                case .read: return (Key.isRead, true)
                case .unread: return (Key.isRead, false)
                case .archive: return (Key.isArchived, true)
                case .unarchive: return (Key.isArchived, false)
                }
            }()
            var changed = false
            for object in try context.fetch(request) where (object.value(forKey: key) as? Bool) != value {
                object.setValue(value, forKey: key)
                changed = true
            }
            if changed { try context.save() }
        }
    }

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

    // MARK: - Helpers

    private static func predicate(for query: InboxStoreQuery) -> NSPredicate {
        typealias Key = InboxStoreModel.Key
        var parts = [NSPredicate(format: "%K == %@", Key.companyID, query.companyID)]
        if let isRead = query.isRead {
            parts.append(NSPredicate(format: "%K == %@", Key.isRead, NSNumber(value: isRead)))
        }
        if let isArchived = query.isArchived {
            parts.append(NSPredicate(format: "%K == %@", Key.isArchived, NSNumber(value: isArchived)))
        }
        if let cursor = query.cursor {
            // Strictly after the cursor in (sortTime DESC, id DESC) order.
            parts.append(NSPredicate(
                format: "%K < %@ OR (%K == %@ AND %K < %@)",
                Key.sortTime, cursor.sortTime as NSDate,
                Key.sortTime, cursor.sortTime as NSDate,
                Key.transmissionID, cursor.id
            ))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
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
