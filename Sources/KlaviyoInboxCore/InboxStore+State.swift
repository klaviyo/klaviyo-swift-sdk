//
//  InboxStore+State.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import CoreData
import Foundation

/// A local state a message can be put into. Read and archive are independent of each other.
package enum InboxMessageState: Equatable {
    case read
    case unread
    case archived
    case unarchived

    /// The stored attribute this state sets, and the value it sets it to.
    fileprivate var attribute: (key: String, value: Bool) {
        typealias Key = InboxStoreModel.Key
        switch self {
        case .read: return (Key.isRead, true)
        case .unread: return (Key.isRead, false)
        case .archived: return (Key.isArchived, true)
        case .unarchived: return (Key.isArchived, false)
        }
    }
}

extension InboxStore {
    /// Puts the message into `state`. Returns whether anything changed, so putting a message into the
    /// state it is already in is a no-op that returns false.
    @discardableResult
    package func setState(
        _ state: InboxMessageState,
        id: String,
        companyID: String
    ) async throws -> Bool {
        try await perform { context in
            defer { context.reset() }
            return try Self.apply(state, id: id, companyID: companyID, in: context)
        }
    }

    /// The change `setState` makes, on a context the caller owns, so a caller that needs more in the
    /// same transaction can run it inside its own `perform`. Saves only when something changed.
    static func apply(
        _ state: InboxMessageState,
        id: String,
        companyID: String,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        typealias Key = InboxStoreModel.Key
        let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            Key.transmissionID, id, Key.companyID, companyID
        )
        request.fetchLimit = 1
        guard let object = try context.fetch(request).first else { return false }
        let (key, value) = state.attribute
        guard object.value(forKey: key) as? Bool != value else { return false }
        object.setValue(value, forKey: key)
        try context.save()
        return true
    }
}
