//
//  InboxRecordTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import KlaviyoInboxCore
import XCTest

final class InboxRecordTests: XCTestCase {
    func testRecordSurvivesAJSONRoundTrip() throws {
        let record = try InboxRecord(
            attribution: InboxAttribution(transmissionID: "tm-1", rawProperties: Data(#"{"tm":"tm-1"}"#.utf8)),
            title: "Title",
            body: "Body",
            defaultDestination: .deepLink(XCTUnwrap(URL(string: "myapp://home"))),
            mediaURL: URL(string: "https://example.com/i.png"),
            mediaType: "png",
            customData: ["k": "v"],
            actions: [
                InboxAction(id: "a", label: "A", destination: .openApp),
                try InboxAction(id: "b", label: "B", destination: .openUrl(XCTUnwrap(URL(string: "https://x.com")))),
                InboxAction(id: "c", label: "C", destination: .unknown("snooze"))
            ],
            sentAt: Date(timeIntervalSince1970: 100),
            receivedAt: Date(timeIntervalSince1970: 200),
            badge: InboxBadge(apsBadge: 1, config: "set_count", value: 2, notificationCount: 3),
            transport: InboxTransportFlags(
                mutableContent: true, contentAvailable: false, priority: "10", sound: "default"
            ),
            rawPayload: Data("{}".utf8)
        )
        let decoded = try JSONDecoder().decode(InboxRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }

    func testDefaultsAreEmptyAndOpenApp() {
        let record = InboxRecord(
            attribution: InboxAttribution(transmissionID: "tm", rawProperties: Data()),
            receivedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(record.defaultDestination, .openApp)
        XCTAssertTrue(record.actions.isEmpty)
        XCTAssertTrue(record.customData.isEmpty)
        XCTAssertNil(record.badge)
        XCTAssertEqual(record.transport, InboxTransportFlags())
    }
}
