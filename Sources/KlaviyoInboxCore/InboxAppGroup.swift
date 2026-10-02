//
//  InboxAppGroup.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation

/// Resolves an App Group identifier to its shared container. A seam so tests can point at a
/// temporary directory (or simulate an unreachable group) instead of a real entitlement.
package struct InboxAppGroup {
    package var containerURL: (String) -> URL?

    package init(containerURL: @escaping (String) -> URL?) {
        self.containerURL = containerURL
    }

    package static let system = InboxAppGroup {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
    }
}
