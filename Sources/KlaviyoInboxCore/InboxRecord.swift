//
//  InboxRecord.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation

/// A delivered Klaviyo push, normalized. Plain data: storage concerns (namespace, read and archive
/// state) belong to the store that wraps it. `rawPayload` keeps the whole payload so a field nobody
/// mapped yet is never lost.
package struct InboxRecord: Equatable, Codable {
    package var attribution: InboxAttribution
    package var title: String?
    package var body: String?
    package var defaultDestination: InboxDestination
    package var mediaURL: URL?
    package var mediaType: String?
    package var customData: [String: String]
    /// In payload order.
    package var actions: [InboxAction]
    package var sentAt: Date?
    /// Set by capture from the device clock, never by the parser.
    package var receivedAt: Date
    package var badge: InboxBadge?
    package var transport: InboxTransportFlags
    /// JSON of the whole `userInfo`, with the device token (`_k.pt`) removed.
    package var rawPayload: Data

    package init(
        attribution: InboxAttribution,
        title: String? = nil,
        body: String? = nil,
        defaultDestination: InboxDestination = .openApp,
        mediaURL: URL? = nil,
        mediaType: String? = nil,
        customData: [String: String] = [:],
        actions: [InboxAction] = [],
        sentAt: Date? = nil,
        receivedAt: Date,
        badge: InboxBadge? = nil,
        transport: InboxTransportFlags = InboxTransportFlags(),
        rawPayload: Data = Data()
    ) {
        self.attribution = attribution
        self.title = title
        self.body = body
        self.defaultDestination = defaultDestination
        self.mediaURL = mediaURL
        self.mediaType = mediaType
        self.customData = customData
        self.actions = actions
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.badge = badge
        self.transport = transport
        self.rawPayload = rawPayload
    }
}

package struct InboxAttribution: Equatable, Codable {
    /// `_k.tm`: unique per delivery, the deduplication key.
    package var transmissionID: String
    /// JSON of `_k` with the device token (`pt`) removed.
    package var rawProperties: Data

    package init(transmissionID: String, rawProperties: Data) {
        self.transmissionID = transmissionID
        self.rawProperties = rawProperties
    }
}

package struct InboxAction: Equatable, Codable {
    package var id: String
    package var label: String
    package var destination: InboxDestination

    package init(id: String, label: String, destination: InboxDestination) {
        self.id = id
        self.label = label
        self.destination = destination
    }
}

package enum InboxDestination: Equatable, Codable {
    case openApp
    case deepLink(URL)
    case openUrl(URL)
    /// An `action` value this SDK version does not know. Kept so a newer server can add types.
    case unknown(String)
}

/// Badge instructions from the payload. Parsed only: applying the badge stays with the rich-push extension.
package struct InboxBadge: Equatable, Codable {
    package var apsBadge: Int?
    package var config: String?
    package var value: Int?
    package var notificationCount: Int?

    package init(apsBadge: Int? = nil, config: String? = nil, value: Int? = nil, notificationCount: Int? = nil) {
        self.apsBadge = apsBadge
        self.config = config
        self.value = value
        self.notificationCount = notificationCount
    }
}

package struct InboxTransportFlags: Equatable, Codable {
    package var mutableContent: Bool?
    package var contentAvailable: Bool?
    package var priority: String?
    package var sound: String?

    package init(
        mutableContent: Bool? = nil,
        contentAvailable: Bool? = nil,
        priority: String? = nil,
        sound: String? = nil
    ) {
        self.mutableContent = mutableContent
        self.contentAvailable = contentAvailable
        self.priority = priority
        self.sound = sound
    }
}
