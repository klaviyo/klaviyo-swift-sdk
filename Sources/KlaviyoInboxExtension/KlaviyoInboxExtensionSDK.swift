//
//  KlaviyoInboxExtensionSDK.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoInboxCore

/// Entry point for the Mobile Inbox Notification Service Extension integration.
///
/// Capture is added by the NSE capture work; this type currently only carries the cross-process
/// enablement lookup that capture gates on.
public enum KlaviyoInboxExtensionSDK {}

extension KlaviyoInboxExtensionSDK {
    /// Whether Mobile Inbox is enabled, read from the App Group named by the extension's
    /// `klaviyo_app_group` Info.plist entry. Needs no running app and no initialized SDK.
    package static func enablement(group: InboxAppGroup = .system) -> InboxEnablement {
        InboxConfigStore(group: group).enablement()
    }
}
