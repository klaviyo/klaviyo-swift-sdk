//
//  InboxStore+Page.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import CoreData
import Foundation

/// A position in a company's messages: the sort position of the last message on a page.
package struct InboxStoreCursor: Equatable {
    package var sortTime: Date
    package var transmissionID: String

    package init(sortTime: Date, transmissionID: String) {
        self.sortTime = sortTime
        self.transmissionID = transmissionID
    }
}

/// One page of a company's stored messages.
package struct InboxStorePage: Equatable {
    package var messages: [StoredInboxMessage]
    /// Pass as `after` for the next page. Nil on the last page.
    package var next: InboxStoreCursor?

    package init(messages: [StoredInboxMessage], next: InboxStoreCursor?) {
        self.messages = messages
        self.next = next
    }
}

extension InboxStore {
    /// One page of the company's messages, newest first by `sortTime`, then `transmissionID`.
    /// Pages by keyset, so a message captured or removed between pages never shifts a page boundary.
    package func page(
        companyID: String,
        limit: Int,
        after: InboxStoreCursor?
    ) async throws -> InboxStorePage {
        try await perform { context in
            defer { context.reset() }
            typealias Key = InboxStoreModel.Key
            let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
            var predicates = [NSPredicate(format: "%K == %@", Key.companyID, companyID)]
            if let after {
                predicates.append(NSPredicate(
                    format: "%K < %@ OR (%K == %@ AND %K < %@)",
                    Key.sortTime, after.sortTime as NSDate,
                    Key.sortTime, after.sortTime as NSDate,
                    Key.transmissionID, after.transmissionID
                ))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [
                NSSortDescriptor(key: Key.sortTime, ascending: false),
                NSSortDescriptor(key: Key.transmissionID, ascending: false)
            ]
            // One extra row tells whether another page exists, without a second query.
            request.fetchLimit = limit + 1
            let fetched = try context.fetch(request)
            let objects = Array(fetched.prefix(limit))
            let messages = try objects.map { try Self.storedMessage(from: $0) }
            let next = fetched.count > limit ? try objects.last.map(Self.cursor(after:)) : nil
            return InboxStorePage(messages: messages, next: next)
        }
    }

    /// Built from the stored `sortTime`, the value the query orders by, so the cursor can never
    /// disagree with how `capture` derived it.
    private static func cursor(after object: NSManagedObject) throws -> InboxStoreCursor {
        typealias Key = InboxStoreModel.Key
        guard let sortTime = object.value(forKey: Key.sortTime) as? Date,
              let transmissionID = object.value(forKey: Key.transmissionID) as? String else {
            throw InboxStoreError.unavailable
        }
        return InboxStoreCursor(sortTime: sortTime, transmissionID: transmissionID)
    }
}
