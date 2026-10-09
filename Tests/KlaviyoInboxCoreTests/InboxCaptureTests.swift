//
//  InboxCaptureTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class InboxCaptureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var temp: InboxTemporaryGroup!
    private var logs: InboxLogRecorder!

    override func setUp() {
        super.setUp()
        temp = InboxTemporaryGroup()
        logs = InboxLogRecorder()
    }

    override func tearDown() {
        temp.remove()
        temp = nil
        logs = nil
        super.tearDown()
    }

    private func register() throws {
        try InboxConfigStore(group: temp.group).enable(localRetentionLimit: 100)
    }

    private func makeCapture(
        sink: InboxCaptureSink,
        group: InboxAppGroup? = nil
    ) -> InboxCapture {
        InboxCapture(group: group ?? temp.group, sink: sink, now: { [now] in now })
    }

    private var klaviyoPush: [AnyHashable: Any] {
        InboxPayloadFixtures.userInfo(InboxPayloadFixtures.full)
    }

    func testEnabledAndValidPayloadReachesTheSinkWithTheDeviceTime() async throws {
        try register()
        let sink = RecordingInboxCaptureSink(result: .captured)
        let result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .captured)
        XCTAssertEqual(sink.records.count, 1)
        XCTAssertEqual(sink.records.first?.attribution.transmissionID, InboxPayloadFixtures.transmissionID)
        XCTAssertEqual(sink.records.first?.receivedAt, now)
    }

    func testNeverRegisteredAndDisabledSkipWithoutParsingOrCallingTheSink() async throws {
        let sink = RecordingInboxCaptureSink()
        var result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .skipped, "never registered")

        try register()
        try InboxConfigStore(group: temp.group).disable()
        result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .skipped, "disabled")
        XCTAssertTrue(sink.records.isEmpty)
    }

    func testUnreachableOrMissingAppGroupSkips() async {
        let sink = RecordingInboxCaptureSink()
        for group in [InboxTemporaryGroup.unreachable, InboxTemporaryGroup.missingIdentifier] {
            let result = await makeCapture(sink: sink, group: group).capture(userInfo: klaviyoPush)
            XCTAssertEqual(result, .skipped)
        }
        XCTAssertTrue(sink.records.isEmpty)
    }

    func testNonKlaviyoPushIsSkippedSilently() async throws {
        try register()
        let sink = RecordingInboxCaptureSink()
        let result = await makeCapture(sink: sink).capture(userInfo: ["aps": ["alert": "hi"]])
        XCTAssertEqual(result, .skipped)
        XCTAssertTrue(sink.records.isEmpty)
        XCTAssertTrue(logs.warnings.isEmpty)
        XCTAssertTrue(logs.errors.isEmpty)
    }

    func testKlaviyoPushWithoutTransmissionIDIsSkippedWithAWarning() async throws {
        try register()
        let sink = RecordingInboxCaptureSink()
        let userInfo = InboxPayloadFixtures.userInfo(#"{"body": {"_k": {"$flow": "F1"}}}"#)
        let result = await makeCapture(sink: sink).capture(userInfo: userInfo)
        XCTAssertEqual(result, .skipped)
        XCTAssertTrue(sink.records.isEmpty)
        XCTAssertEqual(logs.warnings.count, 1)
    }

    func testSinkResultsPassThrough() async throws {
        try register()
        for expected in [InboxCaptureResult.duplicate, .skipped, .captured] {
            let sink = RecordingInboxCaptureSink(result: expected)
            let result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
            XCTAssertEqual(result, expected)
        }
    }

    func testSinkFailureIsLoggedAndReturned() async throws {
        try register()
        let sink = RecordingInboxCaptureSink(result: .failed)
        let result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(logs.errors.count, 1)
    }

    func testCapturingTheSamePushTwiceHandsTheSinkTwoRecordsForItToDeduplicate() async throws {
        // Deduplication by `tm` is the store's job (MAGE-1099); capture must not drop it silently.
        try register()
        let sink = RecordingInboxCaptureSink()
        let capture = makeCapture(sink: sink)
        _ = await capture.capture(userInfo: klaviyoPush)
        _ = await capture.capture(userInfo: klaviyoPush)
        XCTAssertEqual(sink.records.map(\.attribution.transmissionID).count, 2)
        XCTAssertEqual(Set(sink.records.map(\.attribution.transmissionID)).count, 1)
    }

    func testDefaultSinkIsANoOpThatSkips() async throws {
        try register()
        let capture = InboxCapture(group: temp.group, now: { [now] in now })
        let result = await capture.capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .skipped)
    }
}
