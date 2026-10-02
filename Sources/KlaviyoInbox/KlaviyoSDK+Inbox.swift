//
//  KlaviyoSDK+Inbox.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoCore

extension KlaviyoSDKModule {
    /// Turns on Mobile Inbox. Pushes delivered after this call are captured by your Notification
    /// Service Extension, and the setting persists across launches until
    /// ``unregisterFromMobileInbox()`` is called.
    ///
    /// Call it again to change the configuration; a changed ``MobileInboxConfig`` takes effect the
    /// next time this is called.
    ///
    /// - Parameter configuration: The App Group and retention settings.
    /// - Returns: The same instance, for chaining.
    @discardableResult
    public func registerForMobileInbox(configuration: MobileInboxConfig) -> Self {
        MobileInboxRegistration.current.register(configuration)
        return self
    }

    /// Turns off Mobile Inbox and stops capturing pushes.
    ///
    /// - Returns: The same instance, for chaining.
    @discardableResult
    public func unregisterFromMobileInbox() -> Self {
        MobileInboxRegistration.current.unregister()
        return self
    }
}
