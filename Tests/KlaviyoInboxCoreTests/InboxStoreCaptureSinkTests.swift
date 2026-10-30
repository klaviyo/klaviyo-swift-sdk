//
//  InboxStoreCaptureSinkTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class InboxStoreCaptureSinkTests: XCTestCase {
    private var appGroup: InboxAppGroup!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let company = "AbC123"

    override func setUp() {
        super.setUp()
        appGroup = InboxStoreFixtures.temporaryAppGroup()
    }

    private var klaviyoPush: [AnyHashable: Any] {
        InboxPayloadFixtures.userInfo(InboxPayloadFixtures.full)
    }

    private func makeCapture(sink: InboxCaptureSink, timeout: TimeInterval = InboxCapture.defaultTimeout) -> InboxCapture {
        InboxCapture(isAuthorized: { true }, sink: sink, now: { [now] in now }, timeout: timeout)
    }

    private func makeSink(store: @escaping () -> InboxCapturing) -> InboxStoreCaptureSink {
        InboxStoreCaptureSink(appGroup: appGroup, store: store)
    }

    /// Counts how often the sink asks for a store, so a skipped capture can be shown to touch no disk.
    private final class StoreCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var requests: Int { lock.lock(); defer { lock.unlock() }; return count }
        func note() { lock.lock(); count += 1; lock.unlock() }
    }

    func testCapturesThenDeduplicatesWhenTheContextExists() async {
        InboxContext.write(companyID: company, appGroup: appGroup)
        let store = InboxStore(appGroup: appGroup)
        let capture = makeCapture(sink: makeSink { store })
        let first = await capture.capture(userInfo: klaviyoPush)
        let replay = await capture.capture(userInfo: klaviyoPush)
        XCTAssertEqual(first, .captured)
        XCTAssertEqual(replay, .duplicate)
    }

    func testTheRecordIsFiledUnderTheCompanyFromTheContext() async throws {
        InboxContext.write(companyID: company, appGroup: appGroup)
        let store = InboxStore(appGroup: appGroup)
        _ = await makeCapture(sink: makeSink { store }).capture(userInfo: klaviyoPush)
        // Clearing another company leaves the message; clearing its own company removes it.
        try await store.clear(companyID: "other")
        let afterOtherClear = try await store.message(id: InboxPayloadFixtures.transmissionID)
        XCTAssertNotNil(afterOtherClear)
        try await store.clear(companyID: company)
        let afterOwnClear = try await store.message(id: InboxPayloadFixtures.transmissionID)
        XCTAssertNil(afterOwnClear)
    }

    func testWithoutAContextFileTheCaptureIsSkippedAndNoStoreIsCreated() async {
        let counter = StoreCounter()
        let sink = makeSink { counter.note(); return InboxStore(appGroup: self.appGroup) }
        let result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .skipped)
        XCTAssertEqual(counter.requests, 0)
    }

    func testACorruptContextFileIsSkipped() async throws {
        let directory = try XCTUnwrap(appGroup.inboxDirectory())
        try Data("{".utf8).write(to: directory.appendingPathComponent(InboxContext.fileName))
        let counter = StoreCounter()
        let sink = makeSink { counter.note(); return InboxStore(appGroup: self.appGroup) }
        let result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .skipped)
        XCTAssertEqual(counter.requests, 0)
    }

    func testAContextFromANewerSchemaIsSkipped() async throws {
        let directory = try XCTUnwrap(appGroup.inboxDirectory())
        let json = #"{"schemaVersion": 2, "companyID": "AbC123"}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent(InboxContext.fileName))
        let counter = StoreCounter()
        let sink = makeSink { counter.note(); return InboxStore(appGroup: self.appGroup) }
        let result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .skipped)
        XCTAssertEqual(counter.requests, 0)
    }

    func testAStoreSlowerThanTheTimeoutYieldsTimedOutWithoutBlocking() async {
        InboxContext.write(companyID: company, appGroup: appGroup)
        struct SlowStore: InboxCapturing {
            func capture(_ record: InboxRecord, companyID: String) async -> InboxCaptureResult {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return .captured
            }
        }
        let started = Date()
        let result = await makeCapture(sink: makeSink { SlowStore() }, timeout: 0.1)
            .capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testAStoreThatCannotOpenReportsFailedWithoutThrowing() async {
        InboxContext.write(companyID: company, appGroup: appGroup)
        let unreachable = InboxAppGroup(identifier: { "group.test" }, containerURL: { _ in nil })
        let store = InboxStore(appGroup: unreachable)
        let result = await makeCapture(sink: makeSink { store }).capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .failed)
    }

    func testTheDefaultSinkIsTheStoreBackedOne() {
        XCTAssertTrue(InboxCapture.sink is InboxStoreCaptureSink)
    }
}
