//
//  MobileInboxClickByIDTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoCore
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct MobileInboxClickByIDTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private final class Clicks: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [Event] = []

        func add(_ event: Event) {
            lock.lock()
            defer { lock.unlock() }
            events.append(event)
        }

        var all: [Event] {
            lock.lock()
            defer { lock.unlock() }
            return events
        }
    }

    private func makeInbox(company: String?, clicks: Clicks) -> (inbox: MobileInbox, store: InboxStore) {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        let inbox = MobileInbox(store: store, companyID: { company }, dispatchClick: { clicks.add($0) })
        return (inbox, store)
    }

    @Test
    func aClickByIDQueuesTheBrandedEvent() async throws {
        let clicks = Clicks()
        let (inbox, store) = makeInbox(company: company, clicks: clicks)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)

        let queued = try await inbox.trackMessageClick(messageID: "tm-1")

        #expect(queued)
        #expect(clicks.all.count == 1)
        #expect(clicks.all.first?.metric.name.value == "Clicked App Inbox Message")
        #expect(clicks.all.first?.metric.service == "klaviyo")
    }

    @Test
    func aClickByIDOnAButtonUsesThatButton() async throws {
        let clicks = Clicks()
        let (inbox, store) = makeInbox(company: company, clicks: clicks)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)

        let queued = try await inbox.trackMessageClick(messageID: "tm-1", actionID: "a2")

        #expect(queued)
        #expect(clicks.all.first?.properties["Button Label"] as? String == "Web")
    }

    @Test
    func aClickByIDForAMissingMessageQueuesNothing() async throws {
        let clicks = Clicks()
        let (inbox, _) = makeInbox(company: company, clicks: clicks)

        let queued = try await inbox.trackMessageClick(messageID: "gone")

        #expect(!queued)
        #expect(clicks.all.isEmpty)
    }

    @Test
    func aClickByIDForAnUnknownButtonQueuesNothing() async throws {
        let clicks = Clicks()
        let (inbox, store) = makeInbox(company: company, clicks: clicks)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)

        let queued = try await inbox.trackMessageClick(messageID: "tm-1", actionID: "nope")

        #expect(!queued)
        #expect(clicks.all.isEmpty)
    }

    @Test
    func aClickByIDBeforeTheSDKIsInitializedQueuesNothing() async throws {
        let clicks = Clicks()
        let (inbox, store) = makeInbox(company: nil, clicks: clicks)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)

        let queued = try await inbox.trackMessageClick(messageID: "tm-1")

        #expect(!queued)
        #expect(clicks.all.isEmpty)
    }

    @Test
    func aClickByIDDoesNotReachAnotherCompanysMessage() async throws {
        let clicks = Clicks()
        let (inbox, store) = makeInbox(company: company, clicks: clicks)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1, companyID: "Other1")

        let queued = try await inbox.trackMessageClick(messageID: "tm-1")

        #expect(!queued)
        #expect(clicks.all.isEmpty)
    }

    @Test
    func aClickByIDDoesNotChangeMessageState() async throws {
        let clicks = Clicks()
        let (inbox, store) = makeInbox(company: company, clicks: clicks)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)

        try await inbox.trackMessageClick(messageID: "tm-1")

        let message = try await inbox.fetchPage().messages.first
        #expect(message?.isRead == false)
        #expect(message?.isArchived == false)
    }

    @Test
    func aStoreFailureSurfacesAsAStorageFailure() async {
        let clicks = Clicks()
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        let inbox = MobileInbox(
            store: store,
            companyID: { company },
            beforeAccess: { throw InboxError.storageFailure },
            dispatchClick: { clicks.add($0) }
        )

        await #expect(throws: InboxError.storageFailure) {
            try await inbox.trackMessageClick(messageID: "tm-1")
        }
        #expect(clicks.all.isEmpty)
    }
}
#endif
