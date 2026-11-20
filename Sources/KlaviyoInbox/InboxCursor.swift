//
//  InboxCursor.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import Foundation
import KlaviyoInboxCore

/// Why an inbox call failed.
public enum InboxError: Error, Equatable, Sendable {
    /// The on-device store could not complete the call.
    case storageFailure
    /// The cursor is malformed, or did not come from a page of this inbox: another company, another
    /// source, or a query with different filters.
    case invalidCursor
}

/// An opaque position in the inbox. Hosts only pass back the one a page returned.
///
/// The token is versioned JSON holding the sort time and ID of the last message on the page, the
/// company the page was read for, and the query's filters, so a cursor only continues a read for that
/// company with those filters. Its `kind` says which source the position is in, so a server position
/// can share the type later.
public struct InboxCursor: Hashable, Sendable {
    /// The wire form of the position. Opaque: hosts must not parse it, and only pass back the one a
    /// page returned.
    public let token: String

    /// Wraps a token a page returned, for example one a host persisted between launches. The token is
    /// not read here, so any string is accepted; a token that cannot be used surfaces as
    /// ``InboxError/invalidCursor`` when it is passed to ``MobileInbox/fetchPage(_:)``.
    public init(token: String) {
        self.token = token
    }

    private static let version = 1
    private static let localKind = "local"

    init(
        _ position: InboxStoreCursor,
        readFilter: InboxReadFilter,
        archiveFilter: InboxArchiveFilter,
        companyID: String
    ) {
        let payload = CursorPayload(
            version: Self.version,
            kind: Self.localKind,
            sortTime: position.sortTime.timeIntervalSinceReferenceDate,
            transmissionID: position.transmissionID,
            companyID: companyID,
            readFilter: readFilter.payloadValue,
            archiveFilter: archiveFilter.payloadValue
        )
        // Encoding a struct of strings and a double cannot fail.
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        self.init(token: data.base64EncodedString())
    }

    /// The store position this cursor points just past.
    /// - Throws: ``InboxError/invalidCursor`` when the token is malformed, is from another version or
    ///   source, was made for another company, or was made for a query with different filters.
    func position(
        forCompany companyID: String,
        readFilter: InboxReadFilter,
        archiveFilter: InboxArchiveFilter
    ) throws -> InboxStoreCursor {
        guard let data = Data(base64Encoded: token),
              let payload = try? JSONDecoder().decode(CursorPayload.self, from: data),
              payload.version == Self.version,
              payload.kind == Self.localKind,
              payload.companyID == companyID,
              payload.readFilter == readFilter.payloadValue,
              payload.archiveFilter == archiveFilter.payloadValue,
              !payload.transmissionID.isEmpty else {
            throw InboxError.invalidCursor
        }
        return InboxStoreCursor(
            sortTime: Date(timeIntervalSinceReferenceDate: payload.sortTime),
            transmissionID: payload.transmissionID
        )
    }
}

/// The JSON an ``InboxCursor`` token carries. Kept at file scope with full names in Swift and short names
/// on the wire, so a token stays small while its fields read clearly here.
private struct CursorPayload: Codable {
    var version: Int
    var kind: String
    /// Seconds since the reference date, so sub-second sort times survive the round trip.
    var sortTime: Double
    var transmissionID: String
    var companyID: String
    var readFilter: String
    var archiveFilter: String

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case kind = "k"
        case sortTime = "t"
        case transmissionID = "i"
        case companyID = "c"
        case readFilter = "r"
        case archiveFilter = "a"
    }
}

extension InboxReadFilter {
    /// How the filter is spelled in a cursor token. Written out rather than derived from a raw value, so
    /// a token's meaning cannot change with the type's declaration order.
    var payloadValue: String {
        switch self {
        case .all: "all"
        case .unread: "unread"
        case .read: "read"
        }
    }
}

extension InboxArchiveFilter {
    /// How the filter is spelled in a cursor token. Written out rather than derived from a raw value, so
    /// a token's meaning cannot change with the type's declaration order.
    var payloadValue: String {
        switch self {
        case .active: "active"
        case .archived: "archived"
        case .all: "all"
        }
    }
}
