//
//  InboxStoreCaptureSink.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/3/26.
//

import Foundation

/// The sink production capture uses: files each record in the shared App Group store under the company
/// the push itself names (`_k.c`).
///
/// Nothing has to run first. The store is created lazily, on the first capture, so a push delivered before
/// the host has ever launched or called `initialize` is still captured.
package struct InboxStoreCaptureSink: InboxCaptureSink {
    private let store: () -> InboxCapturing

    /// One store per process, created on first use. A static so `InboxCapture`'s default sink shares it.
    private static let shared = InboxStore(appGroup: .system, changeSignal: DarwinInboxChangeSignal())

    package init(store: @escaping () -> InboxCapturing = { InboxStoreCaptureSink.shared }) {
        self.store = store
    }

    package func capture(_ record: InboxRecord) async -> InboxCaptureResult {
        await store().capture(record, companyID: record.attribution.companyID)
    }
}
