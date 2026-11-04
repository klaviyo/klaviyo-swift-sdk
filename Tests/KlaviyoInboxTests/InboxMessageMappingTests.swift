//
//  InboxMessageMappingTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxMessageMappingTests {
    private let base = InboxStoreFixtures.baseDate

    private func stored(
        _ tm: String = "tm-1",
        sentAfterBase: TimeInterval? = 1,
        isRead: Bool = false,
        isArchived: Bool = false
    ) -> StoredInboxMessage {
        let record = InboxStoreFixtures.record(
            tm: tm,
            sentAt: sentAfterBase.map { base.addingTimeInterval($0) },
            receivedAt: base.addingTimeInterval(5)
        )
        return StoredInboxMessage(id: tm, record: record, isRead: isRead, isArchived: isArchived)
    }

    @Test
    func contentFieldsCarryOver() {
        let message = InboxMessage(stored())
        #expect(message.id == "tm-1")
        #expect(message.title == "Sale")
        #expect(message.body == "50% off")
        #expect(message.mediaURL == URL(string: "https://example.com/i.png"))
        #expect(message.mediaType == "png")
        #expect(message.customData == ["k1": "v1"])
    }

    @Test
    func timestampsCarryOverAndASendTimeCanBeAbsent() {
        let sent = InboxMessage(stored(sentAfterBase: 1))
        let unsent = InboxMessage(stored(sentAfterBase: nil))
        #expect(sent.sentAt == base.addingTimeInterval(1))
        #expect(sent.receivedAt == base.addingTimeInterval(5))
        #expect(unsent.sentAt == nil)
    }

    @Test
    func theDefaultDestinationAndEachActionKeepTheirTypeAndURL() {
        let message = InboxMessage(stored())
        #expect(message.defaultDestination.type == .deepLink)
        #expect(message.defaultDestination.url == URL(string: "myapp://home"))
        #expect(message.actions.map(\.id) == ["a1", "a2"])
        #expect(message.actions.map(\.label) == ["Shop", "Web"])
        #expect(message.actions.map(\.destination.type) == [.deepLink, .openUrl])
        #expect(message.actions[1].destination.url == URL(string: "https://example.com"))
    }

    @Test
    func anOpenAppDestinationHasNoURL() {
        var record = InboxStoreFixtures.record(tm: "tm-1")
        record.defaultDestination = .openApp
        let message = InboxMessage(StoredInboxMessage(id: "tm-1", record: record, isRead: false, isArchived: false))
        #expect(message.defaultDestination.type == .openApp)
        #expect(message.defaultDestination.url == nil)
    }

    @Test
    func allFourBadgeValuesCarryOver() {
        let badge = InboxMessage(stored()).badge
        #expect(badge?.apsBadge == 3)
        #expect(badge?.config == "set_count")
        #expect(badge?.value == 5)
        #expect(badge?.notificationCount == 7)
    }

    @Test
    func aPushWithNoBadgeHasNoBadge() {
        var record = InboxStoreFixtures.record(tm: "tm-1")
        record.badge = nil
        let message = InboxMessage(StoredInboxMessage(id: "tm-1", record: record, isRead: false, isArchived: false))
        #expect(message.badge == nil)
    }

    @Test
    func readAndArchivedStateCarryOverIndependently() {
        let readOnly = InboxMessage(stored(isRead: true, isArchived: false))
        let archivedOnly = InboxMessage(stored(isRead: false, isArchived: true))
        #expect(readOnly.isRead)
        #expect(!readOnly.isArchived)
        #expect(!archivedOnly.isRead)
        #expect(archivedOnly.isArchived)
    }

    @Test
    func aCapturedMessageHasTheCapturedSourceAndNoCollapseID() {
        let message = InboxMessage(stored())
        #expect(message.source == .captured)
        #expect(message.collapseID == nil)
    }

    @Test
    func theOpaqueIDIsStableForTheSameMessage() {
        #expect(InboxMessage(stored("tm-9")).id == InboxMessage(stored("tm-9")).id)
        #expect(InboxMessage(stored("tm-9")).id != InboxMessage(stored("tm-8")).id)
    }
}

#endif
