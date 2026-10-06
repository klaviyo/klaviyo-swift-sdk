//
//  EventAPIExtensionTests.swift
//
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

final class EventAPIExtensionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
    }

    func testStampsIdentifiersAndPreservesFields() {
        let event = Event(
            name: .customEvent("test"),
            properties: ["foo": "bar"],
            value: 42,
            valueCurrency: "USD",
            uniqueId: "unique-id"
        )

        let updated = event.updateEventWithIdentifiers(
            email: "test@example.com",
            phoneNumber: "+15551234567",
            externalId: "ext-1",
            pushToken: "token"
        )

        XCTAssertEqual(updated.identifiers?.email, "test@example.com")
        XCTAssertEqual(updated.identifiers?.phoneNumber, "+15551234567")
        XCTAssertEqual(updated.identifiers?.externalId, "ext-1")
        // Existing fields are preserved.
        XCTAssertEqual(updated.properties["foo"] as? String, "bar")
        XCTAssertEqual(updated.value, 42)
        XCTAssertEqual(updated.valueCurrency, "USD")
        XCTAssertEqual(updated.uniqueId, "unique-id")
        XCTAssertEqual(updated.metric.name, .customEvent("test"))
        // Non-opened-push events never receive a push token.
        XCTAssertNil(updated.properties["push_token"])
    }

    func testAddsPushTokenForOpenedPush() {
        let event = Event(name: ._openedPush)

        let updated = event.updateEventWithIdentifiers(
            email: nil,
            phoneNumber: nil,
            externalId: nil,
            pushToken: "token"
        )

        XCTAssertEqual(updated.properties["push_token"] as? String, "token")
    }

    func testOmitsPushTokenForOpenedPushWhenNil() {
        let event = Event(name: ._openedPush)

        let updated = event.updateEventWithIdentifiers(
            email: nil,
            phoneNumber: nil,
            externalId: nil,
            pushToken: nil
        )

        XCTAssertNil(updated.properties["push_token"])
    }
}
