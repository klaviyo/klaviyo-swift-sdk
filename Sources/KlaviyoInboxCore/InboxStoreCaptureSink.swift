//
//  InboxStoreCaptureSink.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation

/// The sink production capture uses: files each record under the company the app wrote into the App
/// Group and hands it to the shared store.
///
/// Before the host has called `initialize` at least once there is no company file, so the capture is
/// skipped and no store is opened. The store is created lazily, on the first capture that has a company.
package struct InboxStoreCaptureSink: InboxCaptureSink {
    private let appGroup: InboxAppGroup
    private let store: () -> InboxCapturing

    /// One store per process, created on first use. A static so `InboxCapture`'s default sink shares it.
    private static let shared = InboxStore(appGroup: .system)

    package init(
        appGroup: InboxAppGroup = .system,
        store: @escaping () -> InboxCapturing = { InboxStoreCaptureSink.shared }
    ) {
        self.appGroup = appGroup
        self.store = store
    }

    package func capture(_ record: InboxRecord) async -> InboxCaptureResult {
        guard let context = InboxContext.read(appGroup: appGroup) else { return .skipped }
        return await store().capture(record, companyID: context.companyID)
    }
}
