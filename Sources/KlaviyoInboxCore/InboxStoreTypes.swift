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
    /// When `isRead` last changed on this device. Nil if it never has.
    package var readUpdatedAt: Date?
    /// When `isArchived` last changed on this device. Nil if it never has.
    package var archivedUpdatedAt: Date?

    package init(
        id: String,
        record: InboxRecord,
        isRead: Bool,
        isArchived: Bool,
        readUpdatedAt: Date? = nil,
        archivedUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.record = record
        self.isRead = isRead
        self.isArchived = isArchived
        self.readUpdatedAt = readUpdatedAt
        self.archivedUpdatedAt = archivedUpdatedAt
    }
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
