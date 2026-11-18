//
//  InboxStoreStateTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

@testable import KlaviyoInboxCore
import CoreData
import Foundation
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

/// A value shared with the `@Sendable` clock closure, guarded by a lock.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

@Suite
struct InboxStoreStateTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private let firstChange = InboxStoreFixtures.baseDate.addingTimeInterval(100)
    private let secondChange = InboxStoreFixtures.baseDate.addingTimeInterval(200)

    /// A clock that returns each of `dates` in turn, then the last one again.
    private func clock(_ dates: Date...) -> @Sendable () -> Date {
        let remaining = LockedBox(dates)
        return { remaining.withValue { $0.count > 1 ? $0.removeFirst() : $0[0] } }
    }

    private func makeStoreWithMessage(
        _ id: String = "tm-1",
        now: @escaping @Sendable () -> Date = { Date() }
    ) async -> InboxStore {
        let store = InboxStoreFixtures.store(appGroup: appGroup, now: now)
        await InboxStoreFixtures.capture(store, id, sentAfterBase: 1)
        return store
    }

    @Test
    func markingAMessageReadSetsItReadAndReportsAChange() async throws {
        let store = await makeStoreWithMessage()
        let changed = try await store.setRead(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(changed == .changed)
        #expect(message?.isRead == true)
    }

    @Test
    func markingAReadMessageUnreadClearsItsReadState() async throws {
        let store = await makeStoreWithMessage()
        try await store.setRead(true, id: "tm-1", companyID: company)
        let changed = try await store.setRead(false, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(changed == .changed)
        #expect(message?.isRead == false)
    }

    @Test
    func archivingAndUnarchivingToggleOnlyTheArchivedState() async throws {
        let store = await makeStoreWithMessage()
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let archived = try await store.message(id: "tm-1")
        try await store.setArchived(false, id: "tm-1", companyID: company)
        let unarchived = try await store.message(id: "tm-1")
        #expect(archived?.isArchived == true)
        #expect(archived?.isRead == false)
        #expect(unarchived?.isArchived == false)
    }

    @Test
    func readAndArchivedAreIndependent() async throws {
        let store = await makeStoreWithMessage()
        try await store.setRead(true, id: "tm-1", companyID: company)
        try await store.setArchived(true, id: "tm-1", companyID: company)
        try await store.setRead(false, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.isRead == false)
        #expect(message?.isArchived == true)
    }

    // MARK: - Updated-at timestamp

    @Test
    func aNewMessageHasNoUpdatedAtAndNoExpiry() async throws {
        let store = await makeStoreWithMessage()
        let message = try await store.message(id: "tm-1")
        #expect(message?.updatedAt == nil)
        #expect(message?.expiresAt == nil)
    }

    @Test
    func changingReadStampsUpdatedAt() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.updatedAt == firstChange)
    }

    @Test
    func changingArchivedStampsUpdatedAt() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.updatedAt == firstChange)
    }

    @Test
    func eachChangeRestampsUpdatedAt() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange, secondChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        let afterRead = try await store.message(id: "tm-1")
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let afterArchive = try await store.message(id: "tm-1")
        #expect(afterRead?.updatedAt == firstChange)
        #expect(afterArchive?.updatedAt == secondChange)
    }

    @Test
    func changingReadBackStampsAgain() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange, secondChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        try await store.setRead(false, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.updatedAt == secondChange)
    }

    @Test
    func aNoOpChangeLeavesUpdatedAtAlone() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange, secondChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        let repeated = try await store.setRead(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(repeated == .unchanged)
        #expect(message?.updatedAt == firstChange)
    }

    @Test
    func aNoOpOnAFreshMessageLeavesUpdatedAtNil() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        let unchanged = try await store.setArchived(false, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(unchanged == .unchanged)
        #expect(message?.updatedAt == nil)
    }

    @Test
    func aStateChangeNeverTouchesExpiresAt() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.expiresAt == nil)
    }

    /// Nothing sets `expiresAt` yet; Phase 1b stores it with a server message. This writes it the way that
    /// work will, to show the column holds a value and survives a later state change.
    @Test
    func aStoredExpiresAtReadsBackAndSurvivesAStateChange() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        let expiry = InboxStoreFixtures.baseDate.addingTimeInterval(86_400)
        try await store.perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
            let object = try #require(context.fetch(request).first)
            object.setValue(expiry, forKey: InboxStoreModel.Key.expiresAt)
            try context.save()
        }
        let stored = try await store.message(id: "tm-1")
        try await store.setRead(true, id: "tm-1", companyID: company)
        let afterChange = try await store.message(id: "tm-1")
        #expect(stored?.expiresAt == expiry)
        #expect(afterChange?.expiresAt == expiry)
    }

    /// `setState` runs inside a caller's transaction, so it must leave its change for the caller to save or
    /// roll back with the rest of its work.
    @Test
    func setStateLeavesTheChangeUncommittedForTheCaller() async throws {
        let store = await makeStoreWithMessage()
        let changed = try await store.perform { context in
            defer { context.reset() }
            let fetched = try InboxStore.message(id: "tm-1", companyID: company, in: context)
            let object = try #require(fetched)
            let changed = object.setState(true, for: .read, at: InboxStoreFixtures.baseDate)
            context.rollback()
            return changed
        }
        #expect(changed)
        let message = try await store.message(id: "tm-1")
        #expect(message?.isRead == false)
    }

    @Test
    func setStateStampsUpdatedAtOnlyOnAChange() async throws {
        let store = await makeStoreWithMessage()
        let date = InboxStoreFixtures.baseDate
        let results = try await store.perform { context in
            defer { context.reset() }
            let fetched = try InboxStore.message(id: "tm-1", companyID: company, in: context)
            let object = try #require(fetched)
            let noOp = object.setState(false, for: .archived, at: date)
            let afterNoOp = object.value(forKey: InboxStoreModel.Key.updatedAt) as? Date
            let first = object.setState(true, for: .archived, at: date)
            let repeated = object.setState(true, for: .archived, at: date.addingTimeInterval(60))
            let stamp = object.value(forKey: InboxStoreModel.Key.updatedAt) as? Date
            return (noOp, afterNoOp, first, repeated, stamp)
        }
        #expect(!results.0)
        #expect(results.1 == nil)
        #expect(results.2)
        #expect(!results.3)
        #expect(results.4 == date)
    }

    @Test
    func applyingAStateTheMessageAlreadyHasChangesNothing() async throws {
        let store = await makeStoreWithMessage()
        let unreadAgain = try await store.setRead(false, id: "tm-1", companyID: company)
        let unarchivedAgain = try await store.setArchived(false, id: "tm-1", companyID: company)
        try await store.setRead(true, id: "tm-1", companyID: company)
        let readAgain = try await store.setRead(true, id: "tm-1", companyID: company)
        // The message exists, so it is reported as unchanged and not as missing.
        #expect(unreadAgain == .unchanged)
        #expect(unarchivedAgain == .unchanged)
        #expect(readAgain == .unchanged)
        #expect(readAgain.messageExists)
    }

    @Test
    func anUnknownMessageChangesNothing() async throws {
        let store = await makeStoreWithMessage()
        let update = try await store.setRead(true, id: "missing", companyID: company)
        #expect(update == .missing)
        #expect(!update.messageExists)
    }

    @Test
    func aStateChangeIsVisibleToAnotherStoreOnTheSameAppGroup() async throws {
        let store = await makeStoreWithMessage()
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let other = InboxStoreFixtures.store(appGroup: appGroup)
        let message = try await other.message(id: "tm-1")
        #expect(message?.isArchived == true)
    }

    @Test
    func replayingACapturedPushKeepsTheMessageState() async throws {
        let store = await makeStoreWithMessage()
        try await store.setRead(true, id: "tm-1", companyID: company)
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let replay = await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let message = try await store.message(id: "tm-1")
        #expect(replay == .duplicate)
        #expect(message?.isRead == true)
        #expect(message?.isArchived == true)
    }

    @Test
    func aMessageOfAnotherCompanyIsLeftAlone() async throws {
        let store = await makeStoreWithMessage()
        let changed = try await store.setRead(true, id: "tm-1", companyID: "XyZ789")
        let message = try await store.message(id: "tm-1")
        #expect(changed == .missing)
        #expect(message?.isRead == false)
    }
}

#endif
