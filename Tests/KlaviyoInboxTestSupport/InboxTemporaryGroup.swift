//
//  InboxTemporaryGroup.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import KlaviyoInboxCore

/// A throwaway directory standing in for App Group containers: each identifier maps to a
/// subdirectory of `root`. Nothing is created until a test writes into it.
package final class InboxTemporaryGroup {
    package let root: URL

    package init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("klaviyo-inbox-tests-\(UUID().uuidString)", isDirectory: true)
    }

    /// The identifier a host would have in its `klaviyo_app_group` Info.plist entry.
    package static let identifier = "group.com.example.app"

    package var group: InboxAppGroup {
        let root = root
        return InboxAppGroup(
            identifier: { Self.identifier },
            containerURL: { root.appendingPathComponent($0, isDirectory: true) }
        )
    }

    /// An identifier is configured but the container can't be reached (entitlement missing).
    package static let unreachable = InboxAppGroup(identifier: { identifier }, containerURL: { _ in nil })

    /// No `klaviyo_app_group` entry in Info.plist.
    package static let missingIdentifier = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })

    package func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
