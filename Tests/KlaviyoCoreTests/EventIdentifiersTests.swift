//
//  EventIdentifiersTests.swift
//
//  Klaviyo Swift SDK
//
//  Created by Belle Lim on 7/23/26.
//

@testable import KlaviyoCore
import XCTest

final class EventIdentifiersTests: XCTestCase {
    func testStampsIdentifiers() {
        let event = Event(name: .customEvent("Test"), properties: ["k": "v"])
        let stamped = event.updateEventWithIdentifiers(
            email: "a@b.com", phoneNumber: "+15551234567", externalId: "ext-1", pushToken: nil
        )
        XCTAssertEqual(stamped.identifiers?.email, "a@b.com")
        XCTAssertEqual(stamped.identifiers?.phoneNumber, "+15551234567")
        XCTAssertEqual(stamped.identifiers?.externalId, "ext-1")
        XCTAssertNil(stamped.properties["push_token"])
    }

    func testOpenedPushInjectsPushTokenProperty() {
        let event = Event(name: ._openedPush, properties: [:])
        let stamped = event.updateEventWithIdentifiers(
            email: nil, phoneNumber: nil, externalId: nil, pushToken: "tok-123"
        )
        XCTAssertEqual(stamped.properties["push_token"] as? String, "tok-123")
    }
}
