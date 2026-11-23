//
//  InboxStore+Page.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import CoreData
import Foundation
import OSLog

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
    ///
    /// `isRead` and `isArchived` narrow the page to messages in that state; nil matches either. Both are
    /// applied by the fetch, so a page is always `limit` matching messages when that many exist, and the
    /// cursor it returns continues the same filtered walk.
    ///
    /// A stored row that cannot be decoded, such as one written by an older `InboxRecord`, is skipped and
    /// logged, so it cannot keep the rest of the inbox from loading. The page can then hold fewer than
    /// `limit` messages while `next` is still set.
    package func page(
        companyID: String,
        limit: Int,
        after: InboxStoreCursor?,
        isRead: Bool? = nil,
        isArchived: Bool? = nil
    ) async throws -> InboxStorePage {
        guard limit > 0 else { return InboxStorePage(messages: [], next: nil) }
        return try await perform { context in
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
            if let isRead {
                predicates.append(NSPredicate(format: "%K == %@", Key.isRead, NSNumber(value: isRead)))
            }
            if let isArchived {
                predicates.append(NSPredicate(format: "%K == %@", Key.isArchived, NSNumber(value: isArchived)))
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
            // Built before decoding, so a row that cannot be decoded still lets the caller page past it.
            let next = fetched.count > limit ? try objects.last.map(Self.cursor(after:)) : nil
            let messages = objects.compactMap { Self.decodedOrSkipped($0) }
            return InboxStorePage(messages: messages, next: next)
        }
    }

    /// How many of the company's messages are unread and not archived, the count an inbox badge shows.
    /// Counted by the store, so no message is loaded to answer.
    package func unreadCount(companyID: String) async throws -> Int {
        try await perform { context in
            defer { context.reset() }
            let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %@", InboxStoreModel.Key.companyID, companyID),
                NSPredicate(format: "%K == %@", InboxStoreModel.Key.isRead, NSNumber(value: false)),
                NSPredicate(format: "%K == %@", InboxStoreModel.Key.isArchived, NSNumber(value: false))
            ])
            return try context.count(for: request)
        }
    }

    private static func decodedOrSkipped(_ object: NSManagedObject) -> StoredInboxMessage? {
        do {
            return try storedMessage(from: object)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.mobileInboxStore.warning(
                    "Skipped a stored message that could not be read (error \(InboxStoreError.diagnosticCode(for: error)))."
                )
            }
            return nil
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
