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
    /// The cursor is malformed, or did not come from a page of this inbox.
    case invalidCursor
}

/// An opaque position in the inbox. Hosts only pass back the one a page returned.
///
/// The token is versioned JSON holding the sort time and ID of the last message on the page and the
/// company the page was read for, so a cursor only continues a read for that company. Its `kind` says
/// which source the position is in, so a server position can share the type later.
public struct InboxCursor: Hashable, Sendable {
    let token: String

    init(token: String) {
        self.token = token
    }

    private static let version = 1
    private static let localKind = "local"

    private struct Payload: Codable {
        var v: Int
        var k: String
        /// Seconds since the reference date, so sub-second sort times survive the round trip.
        var t: Double
        var i: String
        var c: String
    }

    init(_ position: InboxStoreCursor, companyID: String) {
        let payload = Payload(
            v: Self.version,
            k: Self.localKind,
            t: position.sortTime.timeIntervalSinceReferenceDate,
            i: position.transmissionID,
            c: companyID
        )
        // Encoding a struct of strings and a double cannot fail.
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        self.init(token: data.base64EncodedString())
    }

    /// The store position this cursor points just past.
    /// - Throws: ``InboxError/invalidCursor`` when the token is malformed, is from another version or
    ///   source, or was made for another company.
    func position(forCompany companyID: String) throws -> InboxStoreCursor {
        guard let data = Data(base64Encoded: token),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.v == Self.version,
              payload.k == Self.localKind,
              payload.c == companyID,
              !payload.i.isEmpty else {
            throw InboxError.invalidCursor
        }
        return InboxStoreCursor(
            sortTime: Date(timeIntervalSinceReferenceDate: payload.t),
            transmissionID: payload.i
        )
    }
}
