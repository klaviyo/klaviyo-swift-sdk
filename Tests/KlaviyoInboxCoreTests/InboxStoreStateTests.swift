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

    // MARK: - Updated-at timestamps

    @Test
    func aNewMessageHasNoUpdatedAtTimestamps() async throws {
        let store = await makeStoreWithMessage()
        let message = try await store.message(id: "tm-1")
        #expect(message?.readUpdatedAt == nil)
        #expect(message?.archivedUpdatedAt == nil)
    }

    @Test
    func changingReadStampsOnlyReadUpdatedAt() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.readUpdatedAt == firstChange)
        #expect(message?.archivedUpdatedAt == nil)
    }

    @Test
    func changingArchivedStampsOnlyArchivedUpdatedAt() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.archivedUpdatedAt == firstChange)
        #expect(message?.readUpdatedAt == nil)
    }

    @Test
    func aNoOpChangeLeavesTheTimestampAlone() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange, secondChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        let repeated = try await store.setRead(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(repeated == .unchanged)
        #expect(message?.readUpdatedAt == firstChange)
    }

    @Test
    func aNoOpOnAFreshMessageStampsNothing() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        let unchanged = try await store.setRead(false, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(unchanged == .unchanged)
        #expect(message?.readUpdatedAt == nil)
    }

    @Test
    func eachChangeRestampsItsOwnField() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange, secondChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.readUpdatedAt == firstChange)
        #expect(message?.archivedUpdatedAt == secondChange)
    }

    @Test
    func changingReadBackStampsAgain() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange, secondChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        try await store.setRead(false, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.readUpdatedAt == secondChange)
    }

    @Test
    func aNewMessageHasNoCatchAllUpdatedAtAndNoExpiry() async throws {
        let store = await makeStoreWithMessage()
        let message = try await store.message(id: "tm-1")
        #expect(message?.updatedAt == nil)
        #expect(message?.expiredAt == nil)
    }

    @Test
    func anyStateChangeStampsTheCatchAllUpdatedAtWithTheSameTimeAsItsField() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange, secondChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        let afterRead = try await store.message(id: "tm-1")
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let afterArchive = try await store.message(id: "tm-1")
        #expect(afterRead?.updatedAt == firstChange)
        #expect(afterRead?.updatedAt == afterRead?.readUpdatedAt)
        #expect(afterArchive?.updatedAt == secondChange)
        #expect(afterArchive?.updatedAt == afterArchive?.archivedUpdatedAt)
        #expect(afterArchive?.readUpdatedAt == firstChange)
    }

    @Test
    func aNoOpChangeLeavesTheCatchAllUpdatedAtAlone() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange, secondChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        try await store.setRead(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.updatedAt == firstChange)
    }

    @Test
    func aNoOpOnAFreshMessageLeavesTheCatchAllUpdatedAtNil() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        try await store.setArchived(false, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.updatedAt == nil)
    }

    @Test
    func aStateChangeNeverTouchesExpiredAt() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        try await store.setRead(true, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.expiredAt == nil)
    }

    /// Nothing sets `expiredAt` yet; Phase 1b stores it with a server message. This writes it the way that
    /// work will, to show the column holds a value and survives a later state change.
    @Test
    func aStoredExpiredAtReadsBackAndSurvivesAStateChange() async throws {
        let store = await makeStoreWithMessage(now: clock(firstChange))
        let expiry = InboxStoreFixtures.baseDate.addingTimeInterval(86_400)
        try await store.perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: InboxStoreModel.entityName)
            let object = try #require(context.fetch(request).first)
            object.setValue(expiry, forKey: InboxStoreModel.Key.expiredAt)
            try context.save()
        }
        let stored = try await store.message(id: "tm-1")
        try await store.setRead(true, id: "tm-1", companyID: company)
        let afterChange = try await store.message(id: "tm-1")
        #expect(stored?.expiredAt == expiry)
        #expect(afterChange?.expiredAt == expiry)
    }

    /// `apply` runs inside a caller's transaction, so it must leave its change for the caller to save or
    /// roll back with the rest of its work.
    @Test
    func applyLeavesTheChangeUncommittedForTheCaller() async throws {
        let store = await makeStoreWithMessage()
        let changed = try await store.perform { context in
            defer { context.reset() }
            let change = StateChange(
                value: true,
                key: InboxStoreModel.Key.isRead,
                changedAt: InboxStoreFixtures.baseDate
            )
            let changed = try InboxStore.apply(change, id: "tm-1", companyID: company, in: context)
            context.rollback()
            return changed
        }
        #expect(changed == .changed)
        let message = try await store.message(id: "tm-1")
        #expect(message?.isRead == false)
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
