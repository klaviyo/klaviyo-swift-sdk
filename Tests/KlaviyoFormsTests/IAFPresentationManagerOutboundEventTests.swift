//
//  IAFPresentationManagerOutboundEventTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import KlaviyoCore
import XCTest

/// Covers the properties object handed to KlaviyoJS for a native event. `dispatchProfileEvent` has no
/// currency parameter, so currency has to ride inside `properties` to reach JS at all.
@MainActor
final class IAFPresentationManagerOutboundEventTests: XCTestCase {
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
    }

    private func outboundProperties(
        properties: [String: Any]? = nil,
        valueCurrency: String? = nil
    ) -> [String: Any] {
        let event = Event(
            name: .customEvent("Placed Order"),
            properties: properties,
            value: 9.99,
            valueCurrency: valueCurrency
        )
        return IAFPresentationManager.outboundProperties(for: event)
    }

    func testCarriesValueCurrencyUnderTheReservedKey() {
        let properties = outboundProperties(properties: ["form_id": "1"], valueCurrency: "CAD")

        XCTAssertEqual(properties["$value_currency"] as? String, "CAD")
        XCTAssertEqual(properties["form_id"] as? String, "1")
        XCTAssertEqual(properties.count, 2)
    }

    func testAddsNothingWhenCurrencyIsAbsent() {
        let properties = outboundProperties(properties: ["form_id": "1"])

        XCTAssertNil(properties["$value_currency"])
        XCTAssertEqual(properties.count, 1)
    }

    func testDoesNotOverwriteACurrencyAlreadyInProperties() {
        let properties = outboundProperties(
            properties: ["$value_currency": "EUR"],
            valueCurrency: "CAD"
        )

        XCTAssertEqual(properties["$value_currency"] as? String, "EUR")
        XCTAssertEqual(properties.count, 1)
    }

    /// The source event must be left alone. Mutating it would strip or alter the instance held by
    /// `EventBuffer` for replay, since the bridge runs after the event is buffered.
    func testDoesNotMutateTheSourceEvent() {
        let event = Event(
            name: .customEvent("Placed Order"),
            properties: ["form_id": "1"],
            value: 9.99,
            valueCurrency: "CAD"
        )

        let outbound = IAFPresentationManager.outboundProperties(for: event)

        XCTAssertEqual(outbound["$value_currency"] as? String, "CAD")
        XCTAssertNil(event.properties["$value_currency"], "the event's own properties must be untouched")
        XCTAssertEqual(event.properties.count, 1)
        XCTAssertEqual(event.valueCurrency, "CAD")
    }

    func testIsIdempotentAcrossRepeatedDispatches() {
        let event = Event(
            name: .customEvent("Placed Order"),
            properties: ["form_id": "1"],
            value: 9.99,
            valueCurrency: "CAD"
        )

        let first = IAFPresentationManager.outboundProperties(for: event)
        let second = IAFPresentationManager.outboundProperties(for: event)

        XCTAssertEqual(first.count, second.count)
        XCTAssertEqual(second["$value_currency"] as? String, "CAD")
        XCTAssertEqual(second["form_id"] as? String, "1")
    }

    func testSerializesToValidJSONForTheBridge() throws {
        let properties = outboundProperties(properties: ["form_id": "1"], valueCurrency: "CAD")

        let data = try JSONSerialization.data(withJSONObject: properties)
        let roundTripped = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(roundTripped["$value_currency"] as? String, "CAD")
    }
}
