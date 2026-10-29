//
//  InboxContextWriter.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore

/// Hands the API key to the Notification Service Extension, which cannot read the app's own config.
///
/// `KlaviyoSwift.initialize(with:)` finds this class by name at runtime and calls `write(apiKey:)`, so
/// the base SDK never imports `KlaviyoInbox`. Linking the module is enough; there is no registration.
/// The `@objc` name and selector are what that lookup uses: change them in `InboxWriterBridge` too.
@objc(InboxContextWriter)
final class InboxContextWriter: NSObject {
    private static let queue = DispatchQueue(label: "com.klaviyo.inbox.context-writer", qos: .utility)

    /// Writes the company file off the calling thread. Never blocks `initialize` on disk I/O.
    @objc
    class func write(apiKey: String) {
        queue.async { write(apiKey: apiKey, appGroup: .system) }
    }

    @discardableResult
    static func write(apiKey: String, appGroup: InboxAppGroup) -> InboxContextWriteResult {
        InboxContext.write(companyID: apiKey, appGroup: appGroup)
    }
}
