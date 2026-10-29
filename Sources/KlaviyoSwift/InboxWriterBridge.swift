//
//  InboxWriterBridge.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation

/// Tells `KlaviyoInbox`, if the host linked it, which API key the SDK was initialized with.
///
/// `KlaviyoSwift` cannot import `KlaviyoInbox` (the optional module must not be a dependency of the
/// base SDK), so the writer is found by name at runtime. A missing class is a no-op, so hosts without
/// Mobile Inbox are unaffected.
enum InboxWriterBridge {
    /// The `@objc` name of `InboxContextWriter` in `KlaviyoInbox`.
    static let className = "InboxContextWriter"
    /// The selector of its `write(apiKey:)` class method.
    static let selector = "writeWithApiKey:"

    static func notify(apiKey: String, className: String = InboxWriterBridge.className) {
        guard let writer = NSClassFromString(className) as? NSObject.Type else { return }
        let selector = NSSelectorFromString(Self.selector)
        guard writer.responds(to: selector) else { return }
        _ = writer.perform(selector, with: apiKey)
    }
}
