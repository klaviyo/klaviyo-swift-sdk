//
//  InboxStore+State.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import CoreData
import Foundation

/// What a state change found. `unchanged` and `changed` both mean the message exists.
package enum InboxStateUpdate: Equatable {
    case changed
    case unchanged
    case missing

    package var messageExists: Bool { self != .missing }
}

/// A state change to apply: the new value of `key` (`isRead` or `isArchived`), and when it was made.
struct StateChange {
    var value: Bool
    var key: String
    var changedAt: Date
}

extension InboxStore {
    /// Sets whether the message is read. Setting a message to the value it already has is a no-op that
    /// reports `unchanged`.
    @discardableResult
    package func setRead(_ isRead: Bool, id: String, companyID: String) async throws -> InboxStateUpdate {
        try await set(isRead, forKey: InboxStoreModel.Key.isRead, id: id, companyID: companyID)
    }

    /// Sets whether the message is archived, independently of whether it is read. Setting a message to the
    /// value it already has is a no-op that reports `unchanged`.
    @discardableResult
    package func setArchived(_ isArchived: Bool, id: String, companyID: String) async throws -> InboxStateUpdate {
        try await set(isArchived, forKey: InboxStoreModel.Key.isArchived, id: id, companyID: companyID)
    }

    private func set(
        _ value: Bool,
        forKey key: String,
        id: String,
        companyID: String
    ) async throws -> InboxStateUpdate {
        let change = StateChange(value: value, key: key, changedAt: now())
        let update = try await perform { context in
            defer { context.reset() }
            let update = try Self.apply(change, id: id, companyID: companyID, in: context)
            if update == .changed { try context.save() }
            return update
        }
        if update == .changed { changeSignal.post() }
        return update
    }

    /// The change a setter makes, on a context the caller owns, so a caller that needs more in the
    /// same transaction can run it inside its own `perform`. Reports what it found, and leaves
    /// the change unsaved: Core Data saves every pending change in a context, so the caller saves once its
    /// other work has succeeded.
    ///
    /// A change also stamps the matching updated-at with `changedAt`, so Phase 1b can tell which side changed
    /// last. A no-op stamps nothing.
    static func apply(
        _ change: StateChange,
        id: String,
        companyID: String,
        in context: NSManagedObjectContext
    ) throws -> InboxStateUpdate {
        typealias Key = InboxStoreModel.Key
        let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            Key.transmissionID, id, Key.companyID, companyID
        )
        request.fetchLimit = 1
        guard let object = try context.fetch(request).first else { return .missing }
        guard object.value(forKey: change.key) as? Bool != change.value else { return .unchanged }
        object.setValue(change.value, forKey: change.key)
        object.setValue(change.changedAt, forKey: InboxStoreModel.Key.updatedAtKey(for: change.key))
        return .changed
    }
}
