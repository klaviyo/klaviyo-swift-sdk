//
//  InboxMessage+Stored.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import Foundation
import KlaviyoInboxCore

/// Maps a stored message to the public model, so no stored type leaves the module. Core's own names
/// (`InboxAction`, `InboxDestination`, `InboxBadge`) are qualified because the public types share them.
extension InboxMessage {
    init(_ stored: StoredInboxMessage) {
        let record = stored.record
        self.init(
            id: stored.id,
            title: record.title,
            body: record.body,
            defaultDestination: InboxDestination(record.defaultDestination),
            mediaURL: record.mediaURL,
            mediaType: record.mediaType,
            customData: record.customData,
            actions: record.actions.map { action in
                InboxAction(
                    id: action.id,
                    label: action.label,
                    destination: InboxDestination(action.destination)
                )
            },
            sentAt: record.sentAt,
            receivedAt: record.receivedAt,
            collapseID: nil,
            badge: record.badge.map { InboxBadge($0) },
            isRead: stored.isRead,
            isArchived: stored.isArchived,
            source: .captured
        )
    }
}

extension InboxDestination {
    init(_ destination: KlaviyoInboxCore.InboxDestination) {
        switch destination {
        case .openApp:
            self.init(type: .openApp, url: nil)
        case let .deepLink(url):
            self.init(type: .deepLink, url: url)
        case let .openUrl(url):
            self.init(type: .openUrl, url: url)
        }
    }
}

extension InboxBadge {
    init(_ badge: KlaviyoInboxCore.InboxBadge) {
        self.init(
            apsBadge: badge.apsBadge,
            config: badge.config,
            value: badge.value,
            notificationCount: badge.notificationCount
        )
    }
}
