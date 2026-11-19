//
//  InboxCaptureTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxCaptureTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeCapture(sink: InboxCaptureSink, authorized: Bool = true) -> InboxCapture {
        InboxCapture(isAuthorized: { authorized }, sink: sink, now: { [now] in now })
    }

    private var klaviyoPush: [AnyHashable: Any] {
        InboxPayloadFixtures.userInfo(InboxPayloadFixtures.full)
    }

    @Test
    func authorizedAndValidPayloadReachesTheSinkWithTheDeviceTime() async {
        let sink = RecordingInboxCaptureSink(result: .captured)
        let result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
        #expect(result == .captured)
        #expect(sink.records.count == 1)
        #expect(sink.records.first?.attribution.transmissionID == InboxPayloadFixtures.transmissionID)
        #expect(sink.records.first?.receivedAt == now)
    }

    @Test
    func withoutNotificationPermissionSkipsWithoutCallingTheSink() async {
        let sink = RecordingInboxCaptureSink()
        let result = await makeCapture(sink: sink, authorized: false).capture(userInfo: klaviyoPush)
        #expect(result == .skipped)
        #expect(sink.records.isEmpty)
    }

    @Test
    func nonKlaviyoPushIsSkippedSilently() async {
        let sink = RecordingInboxCaptureSink()
        let result = await makeCapture(sink: sink).capture(userInfo: ["aps": ["alert": "hi"]])
        #expect(result == .skipped)
        #expect(sink.records.isEmpty)
    }

    @Test
    func klaviyoPushWithoutTransmissionIDIsSkipped() async {
        let sink = RecordingInboxCaptureSink()
        let userInfo = InboxPayloadFixtures.userInfo(#"{"body": {"_k": {"$flow": "F1"}}}"#)
        let result = await makeCapture(sink: sink).capture(userInfo: userInfo)
        #expect(result == .skipped)
        #expect(sink.records.isEmpty)
    }

    @Test
    func klaviyoPushWithoutCompanyIDIsSkipped() async {
        let sink = RecordingInboxCaptureSink()
        let userInfo = InboxPayloadFixtures.userInfo(
            #"{"body": {"_k": {"tm": "\#(InboxPayloadFixtures.transmissionID)"}}}"#
        )
        let result = await makeCapture(sink: sink).capture(userInfo: userInfo)
        #expect(result == .skipped)
        #expect(sink.records.isEmpty)
    }

    @Test
    func sinkResultsPassThrough() async {
        for expected in [InboxCaptureResult.duplicate, .skipped, .captured, .failed, .timedOut] {
            let sink = RecordingInboxCaptureSink(result: expected)
            let result = await makeCapture(sink: sink).capture(userInfo: klaviyoPush)
            #expect(result == expected)
        }
    }

    @Test
    func capturingTheSamePushTwiceHandsTheSinkTwoRecordsForItToDeduplicate() async {
        // Deduplication by `tm` is the store's job; capture must not drop it silently.
        let sink = RecordingInboxCaptureSink()
        let capture = makeCapture(sink: sink)
        _ = await capture.capture(userInfo: klaviyoPush)
        _ = await capture.capture(userInfo: klaviyoPush)
        #expect(sink.records.map(\.attribution.transmissionID).count == 2)
        #expect(Set(sink.records.map(\.attribution.transmissionID)).count == 1)
    }

    @Test
    func theDefaultSinkIsTheStoreBackedOne() {
        #expect(InboxCapture.sink is InboxStoreCaptureSink)
    }

    @Test
    func slowSinkTimesOutWithoutWaitingForTheWrite() async {
        let sink = SlowSink(delay: 5)
        let capture = InboxCapture(isAuthorized: { true }, sink: sink, now: { [now] in now }, timeout: 0.05)
        let start = Date()
        let result = await capture.capture(userInfo: klaviyoPush)
        #expect(result == .timedOut)
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test
    func sinkThatAnswersBeforeTheTimeoutReturnsItsResult() async {
        let sink = SlowSink(delay: 0.01)
        let capture = InboxCapture(isAuthorized: { true }, sink: sink, now: { [now] in now }, timeout: 5)
        let result = await capture.capture(userInfo: klaviyoPush)
        #expect(result == .captured)
    }
}

private struct SlowSink: InboxCaptureSink {
    let delay: TimeInterval

    func capture(_ record: InboxRecord) async -> InboxCaptureResult {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return .captured
    }
}

#endif
