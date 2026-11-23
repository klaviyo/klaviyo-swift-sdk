//
//  InboxClickEventTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxClickEventTests {
    private func destination(_ type: InboxDestinationType, _ url: String?) -> InboxDestination {
        InboxDestination(type: type, url: url.flatMap { URL(string: $0) })
    }

    private func message(
        id: String = "tm-7",
        defaultDestination: InboxDestination? = nil,
        actions: [InboxAction]? = nil
    ) -> InboxMessage {
        InboxMessage(
            id: id,
            title: nil,
            body: nil,
            defaultDestination: defaultDestination ?? destination(.deepLink, "myapp://sale"),
            mediaURL: nil,
            mediaType: nil,
            customData: [:],
            actions: actions ?? [
                InboxAction(id: "shop", label: "Shop now", destination: destination(.deepLink, "myapp://shop")),
                InboxAction(id: "site", label: "Visit", destination: destination(.openUrl, "https://a.com")),
                InboxAction(id: "open", label: "Open", destination: destination(.openApp, nil))
            ],
            sentAt: nil,
            receivedAt: Date(),
            collapseID: nil,
            badge: nil,
            isRead: false,
            isArchived: false,
            source: .captured
        )
    }

    private func make(
        _ message: InboxMessage,
        action: InboxAction? = nil,
        element: InboxClickElement? = nil
    ) -> Event? {
        InboxClickEvent.make(message: message, action: action, element: element)
    }

    private func property(_ event: Event?, _ key: String) -> String? {
        event?.properties[key] as? String
    }

    @Test
    func theMetricIsBrandedUnderTheKlaviyoService() throws {
        let event = try #require(make(message()))
        #expect(event.metric.name.value == "Clicked App Inbox Message")
        #expect(event.metric.service == "klaviyo")
        #expect(event.priority == .standard)
    }

    @Test
    func aBodyClickReportsTheDefaultDestination() {
        let event = make(message())
        #expect(property(event, "Inbox Message ID") == "tm-7")
        #expect(property(event, "Element") == "body")
        #expect(property(event, "Action Type") == "deep_link")
        #expect(property(event, "Action URL") == "myapp://sale")
        #expect(property(event, "Button Label") == nil)
    }

    @Test
    func aButtonClickReportsTheButtonsDestinationAndLabel() {
        let message = message()
        let event = make(message, action: message.actions[1])
        #expect(property(event, "Element") == "button")
        #expect(property(event, "Action Type") == "open_url")
        #expect(property(event, "Action URL") == "https://a.com")
        #expect(property(event, "Button Label") == "Visit")
    }

    @Test
    func anOpenAppButtonHasNoURL() {
        let message = message()
        let event = make(message, action: message.actions[2])
        #expect(property(event, "Action Type") == "open_app")
        #expect(property(event, "Action URL") == nil)
        #expect(property(event, "Button Label") == "Open")
    }

    @Test
    func anUnknownDestinationTypeIsReportedAsReceived() {
        let unknown = InboxAction(
            id: "x",
            label: "X",
            destination: destination(InboxDestinationType(rawValue: "future_type"), "x://y")
        )
        let event = make(message(actions: [unknown]), action: unknown)
        #expect(property(event, "Action Type") == "future_type")
    }

    @Test
    func eachClickGetsItsOwnUniqueID() throws {
        let first = try #require(make(message()))
        let second = try #require(make(message()))
        #expect(first.uniqueId != second.uniqueId)
    }

    @Test
    func aButtonClickWithoutAnActionIsDropped() {
        #expect(make(message(), element: .button) == nil)
    }

    @Test
    func aMessageIDOutsideTheLimitIsDropped() {
        #expect(make(message(id: String(repeating: "x", count: 65))) == nil)
        #expect(make(message(id: "")) == nil)
        #expect(make(message(id: String(repeating: "x", count: 64))) != nil)
    }

    @Test
    func aURLOverTheLimitIsDropped() {
        let long = message(defaultDestination: destination(.openUrl, "https://a.com/" + String(repeating: "x", count: 2048)))
        #expect(make(long) == nil)
    }

    @Test
    func aButtonLabelOverTheLimitIsDropped() {
        let action = InboxAction(
            id: "a",
            label: String(repeating: "x", count: 256),
            destination: destination(.openApp, nil)
        )
        #expect(make(message(actions: [action]), action: action) == nil)
    }

    @Test
    func trackingAClickDispatchesItWithoutTouchingTheStore() async throws {
        let appGroup = InboxStoreFixtures.temporaryAppGroup()
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await InboxStoreFixtures.capture(store, "tm-7", sentAfterBase: 1)
        let captured = ClickRecorder()
        let inbox = MobileInbox(
            store: store,
            companyID: { InboxStoreFixtures.company },
            dispatchClick: { captured.add($0) }
        )
        let before = try await inbox.fetchPage()
        let stored = try #require(before.messages.first)

        inbox.trackMessageClick(stored)

        #expect(captured.events.count == 1)
        let afterPage = try await inbox.fetchPage()
        let after = try #require(afterPage.messages.first)
        #expect(after.isRead == stored.isRead)
        #expect(after.isArchived == stored.isArchived)
    }

    @Test
    func aStateChangeDoesNotDispatchAClick() async throws {
        let appGroup = InboxStoreFixtures.temporaryAppGroup()
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await InboxStoreFixtures.capture(store, "tm-7", sentAfterBase: 1)
        let captured = ClickRecorder()
        let inbox = MobileInbox(
            store: store,
            companyID: { InboxStoreFixtures.company },
            dispatchClick: { captured.add($0) }
        )

        try await inbox.setMessageState(.read, for: "tm-7")

        #expect(captured.events.isEmpty)
    }
}

private final class ClickRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Event] = []

    var events: [Event] { lock.withLock { recorded } }

    func add(_ event: Event) {
        lock.withLock { recorded.append(event) }
    }
}
#endif
