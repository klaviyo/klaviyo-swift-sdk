//
//  KlaviyoSDK+Inbox.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import KlaviyoCore
import KlaviyoInboxCore

extension KlaviyoSDKModule {
    /// The on-device Mobile Inbox: the Klaviyo pushes this app has received, newest first.
    ///
    /// Reads cover the company `initialize` was called with in this session, so a page is empty until
    /// the SDK is initialized.
    public var mobileInbox: MobileInbox {
        MobileInbox(
            store: InboxStore.shared,
            companyID: {
                MobileInbox.sessionCompanyID(
                    isInitialized: SessionState.isInitialized,
                    apiKey: SDKConfigStore.shared.current.apiKey
                )
            },
            changes: { DarwinInboxChangeSignal().changes() }
        )
    }
}

extension MobileInbox {
    /// The company a read covers. `SDKConfigStore` reloads the previous launch's key from disk, so a key
    /// only counts once `initialize` has begun in this launch: a cold start must not read the last
    /// session's company. An empty key is no company.
    static func sessionCompanyID(isInitialized: Bool, apiKey: String?) -> String? {
        guard isInitialized, let apiKey, !apiKey.isEmpty else { return nil }
        return apiKey
    }
}
