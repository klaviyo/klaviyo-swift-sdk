//
//  MobileInboxFixtures.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport

/// Shared setup for tests that read or change the inbox through ``MobileInbox``, the way a host does.
enum MobileInboxFixtures {
    /// An inbox and the store behind it on a fresh App Group, reading `company`'s messages. A nil
    /// `company` stands in for an SDK that has not been initialized yet.
    static func inbox(
        appGroup: InboxAppGroup,
        company: String?
    ) -> (inbox: MobileInbox, store: InboxStore) {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        return (MobileInbox(store: store, companyID: { company }), store)
    }
}
