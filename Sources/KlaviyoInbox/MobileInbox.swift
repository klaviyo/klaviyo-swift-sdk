//
//  MobileInbox.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import Foundation
import KlaviyoInboxCore

/// Read access to the on-device inbox. Reached through `KlaviyoSDK().mobileInbox`.
///
/// Reads cover the company the SDK was initialized with this session. Before `initialize`, a page is
/// empty. Every call is safe from the main thread, and a store failure surfaces as ``InboxError``.
public struct MobileInbox: Sendable {
    fileprivate let store: InboxStore
    /// The company this session was initialized with, or nil before `initialize`.
    fileprivate let companyID: @Sendable () -> String?
    private let makeChanges: @Sendable () -> AsyncStream<Void>

    init(
        store: InboxStore,
        companyID: @escaping @Sendable () -> String?,
        changes: @escaping @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } }
    ) {
        self.store = store
        self.companyID = companyID
        makeChanges = changes
    }

    /// Fires when the inbox may have changed: a push was captured, a message's state changed, or messages
    /// were cleared, in this process or in the Notification Service Extension. It carries no data. Fetch
    /// the page you are showing again.
    ///
    /// A suspended app does not hear a change that happened while it was suspended, so also fetch again
    /// when your app returns to the foreground.
    public var changes: AsyncStream<Void> {
        makeChanges()
    }

    /// Fetches one page of the current company's messages, newest first. The query's filters choose
    /// which messages the page is made of, so archived messages are left out unless it asks for them.
    /// The page is empty when nothing has been captured yet.
    ///
    /// - Throws: ``InboxError/invalidCursor`` when the query's cursor is malformed, did not come from
    ///   this inbox, or was returned for a query with different filters, and
    ///   ``InboxError/storageFailure`` when the store could not answer.
    public func fetchPage(_ query: InboxQuery = InboxQuery()) async throws -> InboxPage {
        guard let companyID = companyID() else { return InboxPage(messages: [], nextCursor: nil) }
        let after = try query.cursor?.position(
            forCompany: companyID,
            readFilter: query.readFilter,
            archiveFilter: query.archiveFilter
        )
        do {
            let page = try await store.page(
                companyID: companyID,
                limit: query.pageSize,
                after: after,
                isRead: query.readFilter.isRead,
                isArchived: query.archiveFilter.isArchived
            )
            return InboxPage(
                messages: page.messages.map { InboxMessage($0) },
                nextCursor: page.next.map {
                    InboxCursor(
                        $0,
                        readFilter: query.readFilter,
                        archiveFilter: query.archiveFilter,
                        companyID: companyID
                    )
                }
            )
        } catch {
            throw InboxError.storageFailure
        }
    }

    /// Counts the current company's messages that are unread and not archived, the count an inbox
    /// badge shows. Zero when nothing has been captured yet.
    ///
    /// - Throws: ``InboxError/storageFailure`` when the store could not answer.
    public func fetchUnreadCount() async throws -> Int {
        guard let companyID = companyID() else { return 0 }
        do {
            return try await store.unreadCount(companyID: companyID)
        } catch {
            throw InboxError.storageFailure
        }
    }
}

extension MobileInbox {
    /// Puts a message into a state. Read and archived are independent, and putting a message into the
    /// state it is already in changes nothing.
    ///
    /// - Returns: Whether this device has a message with `id` for the current company, whether or not the
    ///   state changed it. `false` when it has none, for example because retention removed it, or when
    ///   the SDK is not initialized yet.
    /// - Throws: ``InboxError/storageFailure`` when the store could not complete the change.
    @discardableResult
    public func setMessageState(_ state: InboxMessageState, for id: String) async throws -> Bool {
        guard let companyID = companyID() else { return false }
        do {
            let update: InboxStateUpdate
            switch state {
            case .read: update = try await store.setRead(true, id: id, companyID: companyID)
            case .unread: update = try await store.setRead(false, id: id, companyID: companyID)
            case .archived: update = try await store.setArchived(true, id: id, companyID: companyID)
            case .unarchived: update = try await store.setArchived(false, id: id, companyID: companyID)
            }
            return update.messageExists
        } catch {
            throw InboxError.storageFailure
        }
    }
}

/// A local state a message can be put into.
public enum InboxMessageState: Hashable, Sendable {
    case read
    case unread
    case archived
    case unarchived
}

/// Which messages ``InboxQuery/readFilter`` returns.
public enum InboxReadFilter: Hashable, Sendable {
    /// Read and unread messages.
    case all
    /// Unread messages only.
    case unread
    /// Read messages only.
    case read
}

/// Which messages ``InboxQuery/archiveFilter`` returns.
public enum InboxArchiveFilter: Hashable, Sendable {
    /// Messages that are not archived.
    case active
    /// Archived messages only.
    case archived
    /// Archived and not archived messages.
    case all
}

/// Which page of the inbox to fetch. Pages run newest first, by send time or by the time this device
/// received the push when the send time is unknown.
///
/// The filters narrow the messages the pages are made of. By default a page holds every message that
/// is not archived, read or unread.
public struct InboxQuery: Hashable, Sendable {
    public static let defaultPageSize = 20
    public static let minPageSize = 1
    public static let maxPageSize = 100

    /// Messages per page, clamped to ``minPageSize`` through ``maxPageSize``.
    public let pageSize: Int
    /// ``InboxPage/nextCursor`` from the previous page, or nil for the first page. A cursor only
    /// continues the query it came from, so a query with a cursor must carry the same filters as the
    /// one that returned it.
    public let cursor: InboxCursor?
    /// Whether read messages, unread messages, or both are returned.
    public let readFilter: InboxReadFilter
    /// Whether archived messages, messages that are not archived, or both are returned.
    public let archiveFilter: InboxArchiveFilter

    public init(
        pageSize: Int = InboxQuery.defaultPageSize,
        cursor: InboxCursor? = nil,
        readFilter: InboxReadFilter = .all,
        archiveFilter: InboxArchiveFilter = .active
    ) {
        self.pageSize = min(max(pageSize, Self.minPageSize), Self.maxPageSize)
        self.cursor = cursor
        self.readFilter = readFilter
        self.archiveFilter = archiveFilter
    }
}

extension InboxReadFilter {
    /// The read state a store query matches, or nil to match either.
    var isRead: Bool? {
        switch self {
        case .all: nil
        case .unread: false
        case .read: true
        }
    }
}

extension InboxArchiveFilter {
    /// The archived state a store query matches, or nil to match either.
    var isArchived: Bool? {
        switch self {
        case .active: false
        case .archived: true
        case .all: nil
        }
    }
}

/// One page of messages.
public struct InboxPage: Hashable, Sendable {
    public let messages: [InboxMessage]
    /// Pass in ``InboxQuery/cursor`` for the next page. Nil on the last page.
    public let nextCursor: InboxCursor?
}
