//
//  InboxContext.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation

package enum InboxContextWriteResult: Equatable {
    case written
    /// The file already holds this company, so nothing was written.
    case unchanged
    /// There was nothing valid to write, or the App Group could not be reached.
    case unavailable
}

/// What the Notification Service Extension needs from the app to file a push under the right company:
/// the public API key the SDK was initialized with. The app writes it into the App Group on
/// `initialize`; the extension reads it on every capture. The key is public, not a secret.
///
/// Only the app writes this file, so there is no write contention between processes.
package struct InboxContext: Equatable {
    package static let schemaVersion = 1
    package static let fileName = "klaviyo-inbox-context.json"

    package let companyID: String

    package init(companyID: String) {
        self.companyID = companyID
    }

    private struct Payload: Codable {
        var schemaVersion: Int
        var companyID: String
    }

    /// The stored context, or nil when the file is missing, unreadable, not valid JSON, has an empty
    /// company, or was written by a newer schema than this reader understands.
    package static func read(appGroup: InboxAppGroup) -> InboxContext? {
        guard let url = fileURL(appGroup: appGroup),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion <= schemaVersion,
              !payload.companyID.isEmpty else {
            return nil
        }
        return InboxContext(companyID: payload.companyID)
    }

    /// Stores the company atomically. An empty key is never written, so the extension keeps skipping
    /// rather than filing pushes under an empty company.
    @discardableResult
    package static func write(companyID: String, appGroup: InboxAppGroup) -> InboxContextWriteResult {
        guard !companyID.isEmpty, let url = fileURL(appGroup: appGroup) else { return .unavailable }
        if read(appGroup: appGroup)?.companyID == companyID { return .unchanged }
        do {
            let data = try JSONEncoder().encode(Payload(schemaVersion: schemaVersion, companyID: companyID))
            try data.write(to: url, options: .atomic)
            return .written
        } catch {
            return .unavailable
        }
    }

    private static func fileURL(appGroup: InboxAppGroup) -> URL? {
        appGroup.inboxDirectory()?.appendingPathComponent(fileName)
    }
}
