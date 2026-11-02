//
//  InboxCapture.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import OSLog
import UserNotifications

package enum InboxCaptureResult: Equatable {
    case captured
    case duplicate
    case skipped
    case failed
    /// The sink did not answer within the capture timeout. The write may still finish in the background.
    case timedOut
}

/// Where a normalized record goes. The shared Inbox store implements this. It must not
/// throw: any failure is reported as `.failed` so capture can never block the notification.
package protocol InboxCaptureSink {
    func capture(_ record: InboxRecord) async -> InboxCaptureResult
}

/// The sink until a store provides one: captures nothing.
package struct NoOpInboxCaptureSink: InboxCaptureSink {
    package init() {}

    package func capture(_ record: InboxRecord) async -> InboxCaptureResult {
        .skipped
    }
}

/// Captures a delivered push: gate on notification permission, parse, hand to the sink. Never throws.
///
/// There is no registration step: linking the Inbox modules turns capture on.
package struct InboxCapture {
    /// The sink production capture uses. The store replaces it when it exists.
    package static var sink: InboxCaptureSink = NoOpInboxCaptureSink()

    /// Longest the notification waits for the sink, in seconds, so a slow store cannot use up the
    /// extension's time.
    package static let defaultTimeout: TimeInterval = 1

    private let isAuthorized: () async -> Bool
    private let sink: InboxCaptureSink
    private let now: () -> Date
    private let timeout: TimeInterval

    package init(
        isAuthorized: @escaping () async -> Bool = InboxCapture.notificationsAuthorized,
        sink: InboxCaptureSink = InboxCapture.sink,
        now: @escaping () -> Date = Date.init,
        timeout: TimeInterval = InboxCapture.defaultTimeout
    ) {
        self.isAuthorized = isAuthorized
        self.sink = sink
        self.now = now
        self.timeout = timeout
    }

    package func capture(userInfo: [AnyHashable: Any]) async -> InboxCaptureResult {
        guard await isAuthorized() else {
            if #available(iOS 14.0, *) {
                Logger.mobileInboxCapture.debug("Notification permission not granted; push not captured to Mobile Inbox.")
            }
            return .skipped
        }
        guard let record = InboxPayloadParser.parse(userInfo: userInfo, receivedAt: now()) else {
            if InboxPayloadParser.hasKlaviyoMetadata(userInfo), #available(iOS 14.0, *) {
                Logger.mobileInboxCapture.warning("Klaviyo push has no usable _k.tm; not captured to Mobile Inbox.")
            }
            return .skipped
        }
        let result = await captureWithinTimeout(record)
        if #available(iOS 14.0, *) {
            switch result {
            case .failed:
                Logger.mobileInboxCapture.error(
                    "Mobile Inbox could not store a captured push; the notification is unaffected."
                )
            case .timedOut:
                Logger.mobileInboxCapture.warning(
                    "Mobile Inbox store write exceeded \(timeout)s; continuing without waiting."
                )
            default:
                break
            }
        }
        return result
    }

    /// Returns whichever finishes first: the sink's answer or the timeout. A timed-out write is not
    /// cancelled, so it can still complete, but nothing waits for it. This is deliberately not a task
    /// group, which would wait for the slow write before returning.
    private func captureWithinTimeout(_ record: InboxRecord) async -> InboxCaptureResult {
        let sink = sink
        let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
        // Both tasks yield into one stream; only the first answer is read, later ones are dropped.
        let answers = AsyncStream<InboxCaptureResult>(bufferingPolicy: .bufferingOldest(1)) { continuation in
            let timer = Task {
                guard await (try? Task.sleep(nanoseconds: nanoseconds)) != nil else { return }
                continuation.yield(.timedOut)
            }
            Task {
                await continuation.yield(sink.capture(record))
                timer.cancel()
            }
        }
        var iterator = answers.makeAsyncIterator()
        return await iterator.next() ?? .timedOut
    }

    /// Whether the user has allowed notifications. The system does not run the extension when they are
    /// off, so this is a safeguard. Capture is skipped when it can't be verified.
    package static func notificationsAuthorized() async -> Bool {
        let status: UNAuthorizationStatus = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings {
                continuation.resume(returning: $0.authorizationStatus)
            }
        }
        switch status {
        case .authorized, .provisional:
            return true
        default:
            if #available(iOS 14.0, *) { return status == .ephemeral }
            return false
        }
    }
}
