//
//  InboxRecordTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import KlaviyoInboxCore
#if canImport(Testing)
import Testing

@Suite
struct InboxRecordTests {
    @Test
    func recordSurvivesAJSONRoundTrip() throws {
        let rawProperties = Data(#"{"tm":"tm-1"}"#.utf8)
        let record = try InboxRecord(
            attribution: InboxAttribution(transmissionID: "tm-1", companyID: "AbC123", rawProperties: rawProperties),
            title: "Title",
            body: "Body",
            defaultDestination: .deepLink(#require(URL(string: "myapp://home"))),
            mediaURL: URL(string: "https://example.com/i.png"),
            mediaType: "png",
            customData: ["k": "v"],
            actions: [
                InboxAction(id: "a", label: "A", destination: .openApp),
                try InboxAction(
                    id: "b",
                    label: "B",
                    destination: .openUrl(#require(URL(string: "https://x.com")))
                ),
                InboxAction(id: "c", label: "C", destination: .deepLink(#require(URL(string: "myapp://c"))))
            ],
            sentAt: Date(timeIntervalSince1970: 100),
            receivedAt: Date(timeIntervalSince1970: 200),
            badge: InboxBadge(apsBadge: 1, config: "set_count", value: 2, notificationCount: 3),
            transport: InboxTransportFlags(
                mutableContent: true, contentAvailable: false, priority: "10", sound: "default"
            )
        )
        let decoded = try JSONDecoder().decode(InboxRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
    }

    @Test
    func defaultsAreEmptyAndOpenApp() {
        let record = InboxRecord(
            attribution: InboxAttribution(transmissionID: "tm", companyID: "AbC123", rawProperties: Data()),
            receivedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(record.defaultDestination == .openApp)
        #expect(record.actions.isEmpty)
        #expect(record.customData.isEmpty)
        #expect(record.badge == nil)
        #expect(record.transport == InboxTransportFlags())
    }
}

#endif
