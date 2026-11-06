//
//  InboxStoreCaptureSinkTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/3/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxStoreCaptureSinkTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let company = InboxPayloadFixtures.companyID

    private var klaviyoPush: [AnyHashable: Any] {
        InboxPayloadFixtures.userInfo(InboxPayloadFixtures.full)
    }

    /// A Klaviyo push with its own `tm` and company, so two companies can share one store.
    private func push(tm: String, company: String) -> [AnyHashable: Any] {
        InboxPayloadFixtures.userInfo(#"{"body": {"_k": {"tm": "\#(tm)", "c": "\#(company)"}}}"#)
    }

    private func makeCapture(
        sink: InboxCaptureSink,
        timeout: TimeInterval = InboxCapture.defaultTimeout
    ) -> InboxCapture {
        InboxCapture(isAuthorized: { true }, sink: sink, now: { [now] in now }, timeout: timeout)
    }

    private func makeSink(store: @escaping () -> InboxCapturing) -> InboxStoreCaptureSink {
        InboxStoreCaptureSink(store: store)
    }

    /// Counts how often the sink asks for a store, so a skipped capture can be shown to touch no disk.
    private final class StoreCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var requests: Int { lock.lock(); defer { lock.unlock() }; return count }
        func note() { lock.lock(); count += 1; lock.unlock() }
    }

    @Test
    func capturesThenDeduplicates() async {
        let store = InboxStore(appGroup: appGroup)
        let capture = makeCapture(sink: makeSink { store })
        let first = await capture.capture(userInfo: klaviyoPush)
        let replay = await capture.capture(userInfo: klaviyoPush)
        #expect(first == .captured)
        #expect(replay == .duplicate)
    }

    @Test
    func recordIsFiledUnderTheCompanyFromThePayload() async throws {
        let store = InboxStore(appGroup: appGroup)
        _ = await makeCapture(sink: makeSink { store }).capture(userInfo: klaviyoPush)
        // Clearing another company leaves the message; clearing its own company removes it.
        try await store.clear(companyID: "other")
        let afterOtherClear = try await store.message(id: InboxPayloadFixtures.transmissionID)
        #expect(afterOtherClear != nil)
        try await store.clear(companyID: company)
        let afterOwnClear = try await store.message(id: InboxPayloadFixtures.transmissionID)
        #expect(afterOwnClear == nil)
    }

    @Test
    func twoCompaniesStayIndependent() async throws {
        let store = InboxStore(appGroup: appGroup)
        let capture = makeCapture(sink: makeSink { store })
        _ = await capture.capture(userInfo: push(tm: "tm-a", company: "AAAAAA"))
        _ = await capture.capture(userInfo: push(tm: "tm-b", company: "BBBBBB"))
        try await store.clear(companyID: "AAAAAA")
        let cleared = try await store.message(id: "tm-a")
        let kept = try await store.message(id: "tm-b")
        #expect(cleared == nil)
        #expect(kept != nil)
    }

    @Test
    func firstPushToAnEmptyAppGroupCreatesTheStoreAndCaptures() async throws {
        let directory = try #require(appGroup.containerURL("group.test"))
        let inboxDirectory = directory.appendingPathComponent(InboxAppGroup.inboxDirectoryName)
        #expect(!(FileManager.default.fileExists(atPath: inboxDirectory.path)))
        let store = InboxStore(appGroup: appGroup)
        let result = await makeCapture(sink: makeSink { store }).capture(userInfo: klaviyoPush)
        #expect(result == .captured)
        #expect(FileManager.default.fileExists(atPath: inboxDirectory.path))
    }

    @Test
    func unreachableAppGroupFailsOpen() async {
        let unreachable = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })
        let store = InboxStore(appGroup: unreachable)
        let result = await makeCapture(sink: makeSink { store }).capture(userInfo: klaviyoPush)
        #expect(result == .failed)
    }

    @Test
    func aPushWithoutACompanyNeverRequestsAStore() async {
        let counter = StoreCounter()
        let sink = makeSink { counter.note(); return InboxStore(appGroup: appGroup) }
        let userInfo = InboxPayloadFixtures.userInfo(
            #"{"body": {"_k": {"tm": "\#(InboxPayloadFixtures.transmissionID)"}}}"#
        )
        let result = await makeCapture(sink: sink).capture(userInfo: userInfo)
        #expect(result == .skipped)
        #expect(counter.requests == 0)
    }

    @Test
    func aStoreSlowerThanTheTimeoutYieldsTimedOutWithoutBlocking() async {
        struct SlowStore: InboxCapturing {
            func capture(_ record: InboxRecord, companyID: String) async -> InboxCaptureResult {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return .captured
            }
        }
        let started = Date()
        let result = await makeCapture(sink: makeSink { SlowStore() }, timeout: 0.1)
            .capture(userInfo: klaviyoPush)
        #expect(result == .timedOut)
        #expect(Date().timeIntervalSince(started) < 1.5)
    }
}

#endif
