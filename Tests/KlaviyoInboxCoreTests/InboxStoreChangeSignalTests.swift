//
//  InboxStoreChangeSignalTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxStoreChangeSignalTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company
    private let signal = RecordingInboxChangeSignal()

    private func makeStore(maxMessages: Int = 100) -> InboxStore {
        InboxStore(appGroup: appGroup, maxMessages: maxMessages, changeSignal: signal)
    }

    @Test
    func aFreshCaptureSignalsAChange() async throws {
        let store = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        #expect(signal.postCount == 1)
    }

    @Test
    func aDuplicateCaptureDoesNotSignal() async throws {
        let store = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        #expect(signal.postCount == 1)
    }

    @Test
    func aStateChangeSignalsOnlyWhenItChangesSomething() async throws {
        let store = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        try await store.setState(.read, id: "tm-1", companyID: company)
        try await store.setState(.read, id: "tm-1", companyID: company)
        try await store.setState(.unarchived, id: "tm-1", companyID: company)
        try await store.setState(.read, id: "missing", companyID: company)
        // One for the capture, one for the single real change.
        #expect(signal.postCount == 2)
    }

    @Test
    func clearingSignalsOnlyWhenRowsWereRemoved() async throws {
        let store = makeStore()
        try await store.clear(companyID: company)
        try await store.clearAll()
        #expect(signal.postCount == 0)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        try await store.clear(companyID: company)
        #expect(signal.postCount == 2)
        await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2)
        try await store.clearAll()
        #expect(signal.postCount == 4)
    }

    @Test
    func aCaptureThatEvictsOlderMessagesStillSignalsOnce() async throws {
        let store = makeStore(maxMessages: 2)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2)
        await InboxStoreFixtures.capture(store, "tm-3", sentAfterBase: 3)
        let evicted = try await store.message(id: "tm-1")
        #expect(evicted == nil)
        #expect(signal.postCount == 3)
    }

    @Test
    func aFailedCaptureDoesNotSignal() async throws {
        let unreachable = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })
        let store = InboxStore(appGroup: unreachable, changeSignal: signal)
        let result = await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        #expect(result == .failed)
        #expect(signal.postCount == 0)
    }
}

#endif
