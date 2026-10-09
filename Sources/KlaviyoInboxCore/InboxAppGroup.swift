//
//  InboxAppGroup.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation

/// The App Group shared by the app and its Notification Service Extension: the one set up for
/// badge counts and rich push, named by the `klaviyo_app_group` Info.plist entry. A seam so tests
/// can supply an identifier and point at a temporary directory (or simulate a missing entry or an
/// unreachable group) instead of a real entitlement.
package struct InboxAppGroup {
    package static let infoDictionaryKey = "klaviyo_app_group"

    package var identifier: () -> String?
    package var containerURL: (String) -> URL?

    package init(identifier: @escaping () -> String?, containerURL: @escaping (String) -> URL?) {
        self.identifier = identifier
        self.containerURL = containerURL
    }

    package static let system = InboxAppGroup(
        identifier: { Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String },
        containerURL: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    )
}
