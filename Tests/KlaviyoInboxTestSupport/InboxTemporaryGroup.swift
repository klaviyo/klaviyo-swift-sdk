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

    package var group: InboxAppGroup {
        let root = root
        return InboxAppGroup { root.appendingPathComponent($0, isDirectory: true) }
    }

    package static let unreachable = InboxAppGroup { _ in nil }

    package func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
