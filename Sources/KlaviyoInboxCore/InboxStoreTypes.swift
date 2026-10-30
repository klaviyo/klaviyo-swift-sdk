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

/// Where the next page starts: just after the last message of the previous one, in
/// `(sortTime, id)` order, so paging stays stable when newer messages arrive. Internal to the store;
/// the public API maps it to its own opaque cursor.
package struct InboxStoreCursor: Equatable {
    package var sortTime: Date
    package var id: String

    package init(sortTime: Date, id: String) {
        self.sortTime = sortTime
        self.id = id
    }
}

/// A page request. A nil filter means no filter on that state.
package struct InboxStoreQuery {
    package var companyID: String
    package var isRead: Bool?
    package var isArchived: Bool?
    package var limit: Int
    package var cursor: InboxStoreCursor?

    package init(
        companyID: String,
        isRead: Bool? = nil,
        isArchived: Bool? = nil,
        limit: Int,
        cursor: InboxStoreCursor? = nil
    ) {
        self.companyID = companyID
        self.isRead = isRead
        self.isArchived = isArchived
        self.limit = limit
        self.cursor = cursor
    }
}

package struct InboxStorePage: Equatable {
    package var messages: [StoredInboxMessage]
    /// Nil when this is the last page.
    package var nextCursor: InboxStoreCursor?

    package init(messages: [StoredInboxMessage], nextCursor: InboxStoreCursor?) {
        self.messages = messages
        self.nextCursor = nextCursor
    }
}

/// The one local-state mutation: setting a state a message is already in is a no-op. It only reaches
/// messages filed under the given company.
package enum InboxLocalState {
    case read
    case unread
    case archive
    case unarchive
}

/// Everything the app reads and changes. The Notification Service Extension only needs `InboxCapturing`.
package protocol InboxStoring: InboxCapturing {
    func fetch(_ query: InboxStoreQuery) async throws -> InboxStorePage
    func message(id: String) async throws -> StoredInboxMessage?
    func setState(_ state: InboxLocalState, companyID: String, ids: [String]) async throws
    func clear(companyID: String) async throws
    func clearAll() async throws
}
