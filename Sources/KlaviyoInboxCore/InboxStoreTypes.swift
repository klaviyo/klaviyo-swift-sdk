//
//  InboxStoreTypes.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation

/// A stored inbox message: the normalized record plus the local state the store owns.
package struct StoredInboxMessage: Equatable {
    /// The push's `tm`.
    package var id: String
    package var record: InboxRecord
    package var isRead: Bool
    package var isArchived: Bool

    package init(id: String, record: InboxRecord, isRead: Bool, isArchived: Bool) {
        self.id = id
        self.record = record
        self.isRead = isRead
        self.isArchived = isArchived
    }
}

/// What the store reports about itself. Carries no record content or identifiers.
package enum InboxStoreEvent: Equatable {
    case opened(milliseconds: Double)
    case migrated(from: Int, to: Int)
    case recovered(reason: String)
    case writeFailed(code: Int)
    case lockContention(retries: Int)
    case degraded(reason: String)
}

package enum InboxStoreError: Error {
    /// The App Group or the store could not be reached.
    case unavailable
    case underlying(Error)
}

/// The write path the app and the extension share. Never throws: any failure is `.failed`.
package protocol InboxCapturing {
    func capture(_ record: InboxRecord, companyID: String) async -> InboxCaptureResult
}
