//
//  InboxCapture.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation

package enum InboxCaptureResult: Equatable {
    case captured
    case duplicate
    case skipped
    case failed
}

/// Where a normalized record goes. The shared Inbox store (MAGE-1099) implements this. It must not
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

/// Captures a delivered push: gate on the persisted enablement, parse, hand to the sink. Never throws.
package struct InboxCapture {
    /// The sink production capture uses. The store replaces it when it exists.
    package static var sink: InboxCaptureSink = NoOpInboxCaptureSink()

    private let store: InboxConfigStore
    private let sink: InboxCaptureSink
    private let now: () -> Date

    package init(
        group: InboxAppGroup = .system,
        sink: InboxCaptureSink = InboxCapture.sink,
        now: @escaping () -> Date = Date.init
    ) {
        store = InboxConfigStore(group: group)
        self.sink = sink
        self.now = now
    }

    package func capture(userInfo: [AnyHashable: Any]) async -> InboxCaptureResult {
        guard case .enabled = store.enablement() else { return .skipped }
        guard let record = InboxPayloadParser.parse(userInfo: userInfo, receivedAt: now()) else {
            if InboxPayloadParser.hasKlaviyoMetadata(userInfo) {
                InboxLog.warning("Klaviyo push has no usable _k.tm; not captured to Mobile Inbox.")
            }
            return .skipped
        }
        let result = await sink.capture(record)
        if result == .failed {
            InboxLog.error("Mobile Inbox could not store a captured push; the notification is unaffected.")
        }
        return result
    }
}
