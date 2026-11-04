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

    /// Fetches one page of the current company's messages, newest first. The page is empty when
    /// nothing has been captured yet.
    ///
    /// - Throws: ``InboxError/invalidCursor`` when the query's cursor is malformed or did not come
    ///   from this inbox, and ``InboxError/storageFailure`` when the store could not answer.
    public func fetchPage(_ query: InboxQuery = InboxQuery()) async throws -> InboxPage {
        guard let companyID = companyID() else { return InboxPage(messages: [], nextCursor: nil) }
        let after = try query.cursor?.position(forCompany: companyID)
        do {
            let page = try await store.page(companyID: companyID, limit: query.pageSize, after: after)
            return InboxPage(
                messages: page.messages.map { InboxMessage($0) },
                nextCursor: page.next.map { InboxCursor($0, companyID: companyID) }
            )
        } catch {
            throw InboxError.storageFailure
        }
    }
}

extension MobileInbox {
    /// Puts a message into a state. Read and archived are independent, and putting a message into the
    /// state it is already in changes nothing. An unknown `id`, or any `id` before the SDK is
    /// initialized, is ignored.
    ///
    /// - Throws: ``InboxError/storageFailure`` when the store could not complete the change.
    public func setMessageState(_ state: InboxMessageState, for id: String) async throws {
        guard let companyID = companyID() else { return }
        do {
            try await store.setState(state.stored, id: id, companyID: companyID)
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

    /// Core names its own state type the same, so it is qualified.
    fileprivate var stored: KlaviyoInboxCore.InboxMessageState {
        switch self {
        case .read: return .read
        case .unread: return .unread
        case .archived: return .archived
        case .unarchived: return .unarchived
        }
    }
}

/// Which page of the inbox to fetch. Pages run newest first, by send time or by the time this device
/// received the push when the send time is unknown.
public struct InboxQuery: Hashable, Sendable {
    public static let defaultPageSize = 20
    public static let minPageSize = 1
    public static let maxPageSize = 100

    /// Messages per page, clamped to ``minPageSize`` through ``maxPageSize``.
    public let pageSize: Int
    /// ``InboxPage/nextCursor`` from the previous page, or nil for the first page.
    public let cursor: InboxCursor?

    public init(pageSize: Int = InboxQuery.defaultPageSize, cursor: InboxCursor? = nil) {
        self.pageSize = min(max(pageSize, Self.minPageSize), Self.maxPageSize)
        self.cursor = cursor
    }
}

/// One page of messages.
public struct InboxPage: Hashable, Sendable {
    public let messages: [InboxMessage]
    /// Pass in ``InboxQuery/cursor`` for the next page. Nil on the last page.
    public let nextCursor: InboxCursor?
}
