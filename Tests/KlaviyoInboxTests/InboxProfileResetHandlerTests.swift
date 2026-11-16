//
//  InboxProfileResetHandlerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/16/26.
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoCore
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxProfileResetHandlerTests {
    /// `KlaviyoSwift` looks the handler up by this name, so a rename here would silently stop the clear.
    @Test
    func theHandlerIsPublishedUnderTheNameKlaviyoSwiftLooksUp() {
        let handlerClass = NSClassFromString(ProfileResetNotifier.inboxHandlerClassName) as? NSObject.Type
        #expect(handlerClass != nil)
        #expect(handlerClass?.init() is ProfileResetHandling)
    }

    @Test
    func aResetClearsEveryCompanysMessages() async throws {
        let store = InboxStoreFixtures.store(appGroup: InboxStoreFixtures.temporaryAppGroup())
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 2, companyID: "XyZ789")
        let handler = InboxProfileResetHandler(clearAll: { try await store.clearAll() })
        handler.profileDidReset()
        // The clear runs off the caller's thread, so wait for it.
        for _ in 0..<100 {
            if try await store.message(id: "tm-1") == nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(try await store.message(id: "tm-1") == nil)
        #expect(try await store.message(id: "other-1") == nil)
    }
}

#endif
