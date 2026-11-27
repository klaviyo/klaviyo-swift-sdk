//
//  InboxStoreBulkStateTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 11/23/26.
//

@testable import KlaviyoInboxCore
import Foundation
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxStoreBulkStateTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company
    private let otherCompany = "XyZ789"
    private let bulkChange = InboxStoreFixtures.baseDate.addingTimeInterval(500)

    /// A store whose clock always reads `bulkChange`, with a signal to count posts.
    private func makeStore(appGroup: InboxAppGroup? = nil) -> (InboxStore, RecordingInboxChangeSignal) {
        let signal = RecordingInboxChangeSignal()
        let date = bulkChange
        let group = appGroup ?? self.appGroup
        return (InboxStoreFixtures.store(appGroup: group, changeSignal: signal, now: { date }), signal)
    }

    /// tm-1 unread/active, tm-2 read/active, tm-3 unread/archived, tm-4 read/archived.
    private func seedFourStates(_ store: InboxStore) async throws {
        for index in 1...4 {
            await InboxStoreFixtures.capture(store, "tm-\(index)", sentAfterBase: TimeInterval(index))
        }
        try await store.setRead(true, id: "tm-2", companyID: company)
        try await store.setArchived(true, id: "tm-3", companyID: company)
        try await store.setRead(true, id: "tm-4", companyID: company)
        try await store.setArchived(true, id: "tm-4", companyID: company)
    }

    private func readStates(_ store: InboxStore) async throws -> [String: Bool] {
        var states: [String: Bool] = [:]
        for index in 1...4 {
            states["tm-\(index)"] = try await store.message(id: "tm-\(index)")?.isRead
        }
        return states
    }

    @Test
    func onlyMessagesMatchingTheFilterChange() async throws {
        let (store, _) = makeStore()
        try await seedFourStates(store)
        let changed = try await store.setState(true, for: .read, companyID: company, isRead: nil, isArchived: false)
        // tm-1 is the only unread, active message; tm-3 is unread but archived.
        #expect(changed == 1)
        let states = try await readStates(store)
        #expect(states == ["tm-1": true, "tm-2": true, "tm-3": false, "tm-4": true])
    }

    @Test
    func anotherCompanysMessagesAreUntouched() async throws {
        let (store, _) = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2, companyID: otherCompany)
        let changed = try await store.setState(true, for: .read, companyID: company)
        let other = try await store.message(id: "tm-2")
        #expect(changed == 1)
        #expect(other?.isRead == false)
        #expect(other?.updatedAt == nil)
    }

    @Test
    func messagesAlreadyInTheStateKeepTheirUpdatedAtAndAreNotCounted() async throws {
        let (store, _) = makeStore()
        try await seedFourStates(store)
        let before = try await store.message(id: "tm-2")
        let changed = try await store.setState(true, for: .read, companyID: company, isArchived: nil)
        let after = try await store.message(id: "tm-2")
        let changedMessage = try await store.message(id: "tm-1")
        // tm-1 and tm-3 were unread; tm-2 and tm-4 were already read.
        #expect(changed == 2)
        #expect(after?.updatedAt == before?.updatedAt)
        #expect(changedMessage?.updatedAt == bulkChange)
    }

    @Test
    func aMessageThatNeverChangedStillHasNoUpdatedAtWhenAlreadyInTheState() async throws {
        let (store, _) = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let changed = try await store.setState(false, for: .read, companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(changed == 0)
        #expect(message?.updatedAt == nil)
    }

    @Test
    func theSignalPostsOncePerCallAndNotWhenNothingChanged() async throws {
        let (store, signal) = makeStore()
        for index in 1...3 {
            await InboxStoreFixtures.capture(store, "tm-\(index)", sentAfterBase: TimeInterval(index))
        }
        let baseline = signal.postCount
        let first = try await store.setState(true, for: .read, companyID: company)
        #expect(first == 3)
        #expect(signal.postCount == baseline + 1)
        let second = try await store.setState(true, for: .read, companyID: company)
        #expect(second == 0)
        #expect(signal.postCount == baseline + 1)
    }

    @Test
    func theSignalDoesNotPostWhenNothingMatches() async throws {
        let (store, signal) = makeStore()
        let changed = try await store.setState(true, for: .read, companyID: company)
        #expect(changed == 0)
        #expect(signal.postCount == 0)
    }

    @Test
    func everyReadAndArchiveFilterCombinationMatchesItsMessages() async throws {
        let reads: [Bool?] = [nil, false, true]
        let archives: [Bool?] = [nil, false, true]
        for isRead in reads {
            for isArchived in archives {
                // A fresh store each time, so no combination sees another's changes.
                let (store, _) = makeStore(appGroup: InboxStoreFixtures.temporaryAppGroup())
                try await seedFourStates(store)
                // Archiving only changes messages that are not archived yet, so the expected count is the
                // matching messages minus the matching ones that already are.
                let matching = [(false, false), (true, false), (false, true), (true, true)].filter {
                    (isRead == nil || $0.0 == isRead) && (isArchived == nil || $0.1 == isArchived)
                }.count
                let changed = try await store.setState(
                    true, for: .archived, companyID: company, isRead: isRead, isArchived: isArchived
                )
                let alreadyArchived = [(false, true), (true, true)].filter {
                    (isRead == nil || $0.0 == isRead) && (isArchived == nil || $0.1 == isArchived)
                }.count
                #expect(changed == matching - alreadyArchived, "isRead \(String(describing: isRead)), isArchived \(String(describing: isArchived))")
            }
        }
    }

    @Test
    func unarchivingMatchesOnlyArchivedMessages() async throws {
        let (store, _) = makeStore()
        try await seedFourStates(store)
        let withActiveFilter = try await store.setState(false, for: .archived, companyID: company, isArchived: false)
        let withArchivedFilter = try await store.setState(false, for: .archived, companyID: company, isArchived: true)
        #expect(withActiveFilter == 0)
        #expect(withArchivedFilter == 2)
    }

    @Test
    func theChangeIsVisibleToAnotherStoreOnTheSameAppGroup() async throws {
        let (store, _) = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        try await store.setState(true, for: .archived, companyID: company)
        let other = InboxStoreFixtures.store(appGroup: appGroup)
        let message = try await other.message(id: "tm-1")
        #expect(message?.isArchived == true)
        #expect(message?.updatedAt == bulkChange)
    }

    @Test
    func unreadCountAndPagesReflectTheChange() async throws {
        let (store, _) = makeStore()
        try await seedFourStates(store)
        let before = try await store.unreadCount(companyID: company)
        try await store.setState(true, for: .read, companyID: company, isArchived: false)
        let after = try await store.unreadCount(companyID: company)
        #expect(before == 1)
        #expect(after == 0)
        let unread = try await store.page(companyID: company, limit: 10, after: nil, isRead: false)
        #expect(unread.messages.map(\.id) == ["tm-3"])
    }

    // MARK: - By ID

    @Test
    func onlyTheListedMessagesChange() async throws {
        let (store, _) = makeStore()
        try await seedFourStates(store)
        let before = try await store.message(id: "tm-3")
        let changed = try await store.setState(true, for: .read, companyID: company, ids: ["tm-1"])
        #expect(changed == 1)
        let states = try await readStates(store)
        #expect(states == ["tm-1": true, "tm-2": true, "tm-3": false, "tm-4": true])
        let untouched = try await store.message(id: "tm-3")
        #expect(untouched?.updatedAt == before?.updatedAt)
    }

    @Test
    func idsAlreadyInTheStateKeepTheirUpdatedAtAndAreNotCounted() async throws {
        let (store, _) = makeStore()
        try await seedFourStates(store)
        let before = try await store.message(id: "tm-2")
        let changed = try await store.setState(true, for: .read, companyID: company, ids: ["tm-1", "tm-2"])
        let after = try await store.message(id: "tm-2")
        let changedMessage = try await store.message(id: "tm-1")
        #expect(changed == 1)
        #expect(after?.updatedAt == before?.updatedAt)
        #expect(changedMessage?.updatedAt == bulkChange)
    }

    @Test
    func unknownAndOtherCompanyIdsAreIgnored() async throws {
        let (store, signal) = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2, companyID: otherCompany)
        let baseline = signal.postCount
        let changed = try await store.setState(true, for: .read, companyID: company, ids: ["tm-1", "tm-2", "missing"])
        let other = try await store.message(id: "tm-2")
        #expect(changed == 1)
        #expect(other?.isRead == false)
        #expect(other?.updatedAt == nil)
        #expect(signal.postCount == baseline + 1)
    }

    @Test
    func duplicateIdsCountOnce() async throws {
        let (store, _) = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let changed = try await store.setState(true, for: .read, companyID: company, ids: ["tm-1", "tm-1", "tm-1"])
        #expect(changed == 1)
    }

    @Test
    func anEmptyListChangesNothingAndPostsNoSignal() async throws {
        let (store, signal) = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let baseline = signal.postCount
        let changed = try await store.setState(true, for: .read, companyID: company, ids: [])
        let message = try await store.message(id: "tm-1")
        #expect(changed == 0)
        #expect(message?.isRead == false)
        #expect(signal.postCount == baseline)
    }

    @Test
    func theSignalPostsOncePerIdCallAndNotWhenNothingChanged() async throws {
        let (store, signal) = makeStore()
        for index in 1...3 {
            await InboxStoreFixtures.capture(store, "tm-\(index)", sentAfterBase: TimeInterval(index))
        }
        let baseline = signal.postCount
        let first = try await store.setState(true, for: .read, companyID: company, ids: ["tm-1", "tm-2"])
        #expect(first == 2)
        #expect(signal.postCount == baseline + 1)
        let second = try await store.setState(true, for: .read, companyID: company, ids: ["tm-1", "tm-2", "missing"])
        #expect(second == 0)
        #expect(signal.postCount == baseline + 1)
    }

    @Test
    func archivingByIdLeavesReadAloneAndUnarchivingRestores() async throws {
        let (store, _) = makeStore()
        try await seedFourStates(store)
        let archived = try await store.setState(true, for: .archived, companyID: company, ids: ["tm-1", "tm-3"])
        let unarchived = try await store.setState(false, for: .archived, companyID: company, ids: ["tm-3", "tm-4"])
        let first = try await store.message(id: "tm-1")
        let fourth = try await store.message(id: "tm-4")
        #expect(archived == 1)
        #expect(unarchived == 2)
        #expect(first?.isArchived == true)
        #expect(first?.isRead == false)
        #expect(fourth?.isArchived == false)
        #expect(fourth?.isRead == true)
    }

    /// More IDs than one batch binds: the counts add up across batches and the signal still posts once.
    @Test
    func aVeryLongListRunsInChunksAndPostsOneSignal() async throws {
        let (store, signal) = makeStore()
        for index in 1...3 {
            await InboxStoreFixtures.capture(store, "tm-\(index)", sentAfterBase: TimeInterval(index))
        }
        let filler = (0..<(InboxStore.maxIDsPerBatch * 2 + 100)).map { "unknown-\($0)" }
        // The three real IDs land in different chunks.
        let ids = ["tm-1"] + filler.prefix(InboxStore.maxIDsPerBatch)
            + ["tm-2"] + filler.dropFirst(InboxStore.maxIDsPerBatch) + ["tm-3"]
        let baseline = signal.postCount
        let changed = try await store.setState(true, for: .read, companyID: company, ids: ids)
        #expect(changed == 3)
        #expect(signal.postCount == baseline + 1)
        for index in 1...3 {
            let message = try await store.message(id: "tm-\(index)")
            #expect(message?.isRead == true)
            #expect(message?.updatedAt == bulkChange)
        }
    }

    @Test
    func chunkedUpdatesSumEveryChunk() {
        var chunks: [[String]] = []
        let outcome = InboxStore.updateInChunks(["a", "b", "c", "d", "e"], of: 2) { chunk in
            chunks.append(chunk)
            return chunk.count
        }
        #expect(chunks == [["a", "b"], ["c", "d"], ["e"]])
        #expect(outcome.changed == 5)
        #expect(outcome.failure == nil)
    }

    /// Batch updates are already written when a later chunk fails, so their count is kept for the signal.
    @Test
    func aFailingChunkKeepsTheCountOfTheChunksBeforeItAndStops() {
        struct ChunkFailed: Error {}
        var calls = 0
        let outcome = InboxStore.updateInChunks(["a", "b", "c", "d", "e"], of: 2) { chunk in
            calls += 1
            if calls == 2 { throw ChunkFailed() }
            return chunk.count
        }
        #expect(calls == 2)
        #expect(outcome.changed == 2)
        #expect(outcome.failure is ChunkFailed)
    }
}

#endif
