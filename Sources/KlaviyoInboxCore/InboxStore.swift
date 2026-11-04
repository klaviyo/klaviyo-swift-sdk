//
//  InboxStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import CoreData
import Foundation
import OSLog

/// The Inbox's Core Data store (SQLite, WAL) in the App Group, shared by the app and the Notification
/// Service Extension. Each process owns its own coordinator and context; SQLite handles the locking
/// between them. No Core Data type leaves this module.
///
/// The initializer parameters are test seams, not host options. Production passes only `appGroup`.
// `@unchecked Sendable`: the only mutable state lives in `Stack`, and is touched only on the context's
// serial queue. The stored closures are never mutated after init.
package final class InboxStore: InboxCapturing, @unchecked Sendable {
    /// Messages kept per company; the oldest by `sortTime` are removed beyond this.
    package static let defaultMaxMessages = 100
    package static let storeFileName = "klaviyo-inbox.sqlite"

    let appGroup: InboxAppGroup
    let maxMessages: Int

    /// One coordinator and one private-queue context for the life of the store. Creating them does no
    /// I/O; the persistent store is added on the context's queue the first time it is needed.
    private final class Stack: @unchecked Sendable {
        let coordinator: NSPersistentStoreCoordinator
        let context: NSManagedObjectContext
        /// Only read or written on the context's queue.
        var isLoaded = false

        init(model: NSManagedObjectModel) {
            coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            // A uniqueness conflict must throw, not merge: a merge policy would let a second writer's save
            // "succeed" and report `.captured` for a push another process already stored, and could overwrite
            // that row's read/archived state. The throw is caught in `insert` and mapped to `.duplicate`.
            context.mergePolicy = NSErrorMergePolicy
        }
    }

    private let stack: Stack

    package init(
        appGroup: InboxAppGroup,
        maxMessages: Int = InboxStore.defaultMaxMessages
    ) {
        self.appGroup = appGroup
        self.maxMessages = maxMessages
        stack = Stack(model: InboxStoreModel.current)
    }

    // MARK: - Capture

    package func capture(_ record: InboxRecord, companyID: String) async -> InboxCaptureResult {
        do {
            let payload = try JSONEncoder().encode(record)
            let sortTime = record.sentAt ?? record.receivedAt
            return try await perform { context in
                defer { context.reset() }
                let result = try Self.insert(
                    record,
                    payload: payload,
                    sortTime: sortTime,
                    companyID: companyID,
                    into: context
                )
                // Only a fresh insert can push the company over the limit; a replay never deletes. The message
                // is already saved, so a failed trim must not report the capture as failed: the next
                // capture trims everything beyond the limit.
                if result == .captured {
                    do {
                        try Self.trim(companyID: companyID, keeping: self.maxMessages, in: context)
                    } catch {
                        if #available(iOS 14.0, *) {
                            Logger.mobileInboxStore.warning(
                                "Retention trim failed (error \(InboxStoreError.diagnosticCode(for: error))); the message is stored."
                            )
                        }
                    }
                }
                return result
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.mobileInboxStore.error("Store write failed (error \(InboxStoreError.diagnosticCode(for: error))).")
            }
            return .failed
        }
    }

    private static func insert(
        _ record: InboxRecord,
        payload: Data,
        sortTime: Date,
        companyID: String,
        into context: NSManagedObjectContext
    ) throws -> InboxCaptureResult {
        let transmissionID = record.attribution.transmissionID
        if try exists(transmissionID: transmissionID, in: context) { return .duplicate }

        guard let entity = NSEntityDescription.entity(
            forEntityName: InboxStoreModel.entityName,
            in: context
        ) else {
            throw InboxStoreError.unavailable
        }
        typealias Key = InboxStoreModel.Key
        let message = NSManagedObject(entity: entity, insertInto: context)
        message.setValue(companyID, forKey: Key.companyID)
        message.setValue(transmissionID, forKey: Key.transmissionID)
        message.setValue(sortTime, forKey: Key.sortTime)
        message.setValue(payload, forKey: Key.payload)
        do {
            try context.save()
        } catch {
            context.rollback()
            // Another writer may have inserted the same `tm` between the check and the save.
            if try exists(transmissionID: transmissionID, in: context) { return .duplicate }
            throw error
        }
        return .captured
    }

    private static func exists(transmissionID: String, in context: NSManagedObjectContext) throws -> Bool {
        let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
        request.predicate = NSPredicate(format: "%K == %@", InboxStoreModel.Key.transmissionID, transmissionID)
        request.fetchLimit = 1
        return try context.count(for: request) > 0
    }

    // MARK: - Read

    package func message(id: String) async throws -> StoredInboxMessage? {
        try await perform { context in
            defer { context.reset() }
            let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
            request.predicate = NSPredicate(format: "%K == %@", InboxStoreModel.Key.transmissionID, id)
            request.fetchLimit = 1
            guard let object = try context.fetch(request).first else { return nil }
            return try Self.storedMessage(from: object)
        }
    }

    static func storedMessage(from object: NSManagedObject) throws -> StoredInboxMessage {
        typealias Key = InboxStoreModel.Key
        guard let payload = object.value(forKey: Key.payload) as? Data,
              let transmissionID = object.value(forKey: Key.transmissionID) as? String else {
            throw InboxStoreError.unavailable
        }
        return try StoredInboxMessage(
            id: transmissionID,
            record: JSONDecoder().decode(InboxRecord.self, from: payload),
            isRead: object.value(forKey: Key.isRead) as? Bool ?? false,
            isArchived: object.value(forKey: Key.isArchived) as? Bool ?? false
        )
    }

    // MARK: - Context access

    /// Note: a SQLite lock held by another process blocks the save on this queue for as long as the lock is
    /// held. `InboxCapture` still returns `.timedOut` after its timeout, but later captures in this process
    /// queue behind the blocked one until the lock clears.
    ///
    /// Runs `work` on the store's private queue, opening the persistent store first if needed. Every
    /// public method goes through here; no context is touched from any other thread.
    func perform<T>(_ work: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let stack = stack
        return try await withCheckedThrowingContinuation { continuation in
            stack.context.perform {
                continuation.resume(with: Result {
                    try self.loadIfNeeded(stack)
                    return try work(stack.context)
                })
            }
        }
    }

    private func loadIfNeeded(_ stack: Stack) throws {
        guard !stack.isLoaded else { return }
        guard let directory = appGroup.inboxDirectory() else {
            if #available(iOS 14.0, *) {
                Logger.mobileInboxStore.error("App Group container unavailable; the Inbox store cannot be opened.")
            }
            throw InboxStoreError.unavailable
        }
        let opener = InboxStoreOpener()
        try opener.open(stack.coordinator, at: directory.appendingPathComponent(Self.storeFileName))
        stack.isLoaded = true
    }
}
