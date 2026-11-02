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

    private func makeCapture(sink: InboxCaptureSink, authorized: Bool = true) -> InboxCapture {
        InboxCapture(isAuthorized: { authorized }, sink: sink, now: { [now] in now })
    }

    private var klaviyoPush: [AnyHashable: Any] {
        InboxPayloadFixtures.userInfo(InboxPayloadFixtures.full)
    }

    func testAuthorizedAndValidPayloadReachesTheSinkWithTheDeviceTime() async {
        let sink = RecordingInboxCaptureSink(result: .captured)
        let result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .captured)
        XCTAssertEqual(sink.records.count, 1)
        XCTAssertEqual(sink.records.first?.attribution.transmissionID, InboxPayloadFixtures.transmissionID)
        XCTAssertEqual(sink.records.first?.receivedAt, now)
    }

    func testWithoutNotificationPermissionSkipsWithoutCallingTheSink() async {
        let sink = RecordingInboxCaptureSink()
        let result = await makeCapture(sink: sink, authorized: false).capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .skipped)
        XCTAssertTrue(sink.records.isEmpty)
    }

    func testNonKlaviyoPushIsSkippedSilently() async {
        let sink = RecordingInboxCaptureSink()
        let result = await makeCapture(sink: sink).capture(userInfo: ["aps": ["alert": "hi"]])
        XCTAssertEqual(result, .skipped)
        XCTAssertTrue(sink.records.isEmpty)
    }

    func testKlaviyoPushWithoutTransmissionIDIsSkipped() async {
        let sink = RecordingInboxCaptureSink()
        let userInfo = InboxPayloadFixtures.userInfo(#"{"body": {"_k": {"$flow": "F1"}}}"#)
        let result = await makeCapture(sink: sink).capture(userInfo: userInfo)
        XCTAssertEqual(result, .skipped)
        XCTAssertTrue(sink.records.isEmpty)
    }

    func testSinkResultsPassThrough() async {
        for expected in [InboxCaptureResult.duplicate, .skipped, .captured, .failed, .timedOut] {
            let sink = RecordingInboxCaptureSink(result: expected)
            let result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
            XCTAssertEqual(result, expected)
        }
    }

    func testCapturingTheSamePushTwiceHandsTheSinkTwoRecordsForItToDeduplicate() async {
        // Deduplication by `tm` is the store's job; capture must not drop it silently.
        let sink = RecordingInboxCaptureSink()
        let capture = makeCapture(sink: sink)
        _ = await capture.capture(userInfo: klaviyoPush)
        _ = await capture.capture(userInfo: klaviyoPush)
        XCTAssertEqual(sink.records.map(\.attribution.transmissionID).count, 2)
        XCTAssertEqual(Set(sink.records.map(\.attribution.transmissionID)).count, 1)
    }

    func testDefaultSinkIsANoOpThatSkips() async {
        let capture = InboxCapture(isAuthorized: { true }, now: { [now] in now })
        let result = await capture.capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .skipped)
    }

    func testSlowSinkTimesOutWithoutWaitingForTheWrite() async {
        let sink = SlowSink(delay: 5)
        let capture = InboxCapture(isAuthorized: { true }, sink: sink, now: { [now] in now }, timeout: 0.05)
        let start = Date()
        let result = await capture.capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testSinkThatAnswersBeforeTheTimeoutReturnsItsResult() async {
        let sink = SlowSink(delay: 0.01)
        let capture = InboxCapture(isAuthorized: { true }, sink: sink, now: { [now] in now }, timeout: 5)
        let result = await capture.capture(userInfo: klaviyoPush)
        XCTAssertEqual(result, .captured)
    }
}

private struct SlowSink: InboxCaptureSink {
    let delay: TimeInterval

    func capture(_ record: InboxRecord) async -> InboxCaptureResult {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return .captured
    }
}
