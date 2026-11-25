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

/// A message state a user can change.
package enum InboxStateField {
    case read
    case archived

    /// The Bool attribute that holds the state.
    var key: String {
        switch self {
        case .read: InboxStoreModel.Key.isRead
        case .archived: InboxStoreModel.Key.isArchived
        }
    }
}

extension NSManagedObject {
    /// Sets `field` to `value` and stamps `updatedAt` with `date`. Returns whether anything changed: a value
    /// the message already has is a no-op that stamps nothing. The change is left unsaved for the caller.
    func setState(_ value: Bool, for field: InboxStateField, at date: Date) -> Bool {
        guard self.value(forKey: field.key) as? Bool != value else { return false }
        setValue(value, forKey: field.key)
        setValue(date, forKey: InboxStoreModel.Key.updatedAt)
        return true
    }
}

extension InboxStore {
    /// Sets whether the message is read. Setting a message to the value it already has is a no-op that
    /// reports `unchanged`.
    @discardableResult
    package func setRead(_ isRead: Bool, id: String, companyID: String) async throws -> InboxStateUpdate {
        try await set(isRead, for: .read, id: id, companyID: companyID)
    }

    /// Sets whether the message is archived, independently of whether it is read. Setting a message to the
    /// value it already has is a no-op that reports `unchanged`.
    @discardableResult
    package func setArchived(_ isArchived: Bool, id: String, companyID: String) async throws -> InboxStateUpdate {
        try await set(isArchived, for: .archived, id: id, companyID: companyID)
    }

    private func set(
        _ value: Bool,
        for field: InboxStateField,
        id: String,
        companyID: String
    ) async throws -> InboxStateUpdate {
        let changedAt = now()
        let update = try await perform { context -> InboxStateUpdate in
            defer { context.reset() }
            guard let object = try Self.message(id: id, companyID: companyID, in: context) else { return .missing }
            guard object.setState(value, for: field, at: changedAt) else { return .unchanged }
            try context.save()
            return .changed
        }
        if update == .changed { changeSignal.post() }
        return update
    }

    /// Sets `field` to `value` on the company's messages that match `isRead` and `isArchived` (nil matches
    /// either) and are not already in that state, and returns how many changed. The changed messages all get
    /// the same `updatedAt`; the rest keep theirs.
    ///
    /// One batch `UPDATE`: atomic, and no message is loaded, so the Notification Service Extension's writes
    /// don't queue behind a long fetch. Posts the change signal once, and only if something changed.
    @discardableResult
    package func setState(
        _ value: Bool,
        for field: InboxStateField,
        companyID: String,
        isRead: Bool? = nil,
        isArchived: Bool? = nil
    ) async throws -> Int {
        let changedAt = now()
        let changed = try await perform { context -> Int in
            defer { context.reset() }
            typealias Key = InboxStoreModel.Key
            var predicates = [
                NSPredicate(format: "%K == %@", Key.companyID, companyID),
                NSPredicate(format: "%K != %@", field.key, NSNumber(value: value))
            ]
            if let isRead {
                predicates.append(NSPredicate(format: "%K == %@", Key.isRead, NSNumber(value: isRead)))
            }
            if let isArchived {
                predicates.append(NSPredicate(format: "%K == %@", Key.isArchived, NSNumber(value: isArchived)))
            }
            let update = NSBatchUpdateRequest(entityName: InboxStoreModel.entityName)
            update.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            update.propertiesToUpdate = [field.key: value, Key.updatedAt: changedAt]
            update.resultType = .updatedObjectIDsResultType
            let result = try context.execute(update) as? NSBatchUpdateResult
            guard let updated = result?.result as? [NSManagedObjectID] else { return 0 }
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSUpdatedObjectsKey: updated],
                into: [context]
            )
            return updated.count
        }
        if changed > 0 { changeSignal.post() }
        return changed
    }

    /// The company's message with `id`, or nil when the company has none.
    package func message(id: String, companyID: String) async throws -> StoredInboxMessage? {
        try await perform { context in
            defer { context.reset() }
            guard let object = try Self.message(id: id, companyID: companyID, in: context) else { return nil }
            return try Self.storedMessage(from: object)
        }
    }

    /// The managed object for a company's message, or nil if there is none.
    static func message(id: String, companyID: String, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        typealias Key = InboxStoreModel.Key
        let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            Key.transmissionID, id, Key.companyID, companyID
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
