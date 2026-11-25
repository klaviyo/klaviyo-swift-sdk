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
    /// When the message was sent: the push's `_k.timestamp`.
    package var sentAt: Date
    /// When this device first stored the message. Set once; read, archive and update never change it.
    package var receivedAt: Date
    /// When the message last changed (read or archive) on this device. Nil if it never has; a capture does not set it.
    package var updatedAt: Date?
    /// When the message expires. Nil means it does not, which is always the case for a captured push.
    package var expiresAt: Date?

    package init(
        id: String,
        record: InboxRecord,
        isRead: Bool,
        isArchived: Bool,
        sentAt: Date,
        receivedAt: Date,
        updatedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.record = record
        self.isRead = isRead
        self.isArchived = isArchived
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
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
