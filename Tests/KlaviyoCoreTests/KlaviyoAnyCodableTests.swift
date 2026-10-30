//
//  KlaviyoAnyCodableTests.swift
//
//  Klaviyo Swift SDK
//

@testable import KlaviyoCore
import XCTest

/// Guards the vendored AnyCodable against wire-format drift for the mixed, nested
/// `[String: Any]` properties the SDK sends on events and profiles.
final class KlaviyoAnyCodableTests: XCTestCase {
    private let mixed: [String: Any] = [
        "string": "hello",
        "int": 42,
        "double": 9.99,
        "bool": true,
        "nsNumberBool": NSNumber(value: false),
        "null": NSNull(),
        "array": [1, "two", 3.5, false] as [Any],
        "nested": [
            "items": [["sku": "A1", "qty": 2], ["sku": "B2", "qty": 1]],
            "meta": ["source": "app", "depth": ["level": 3]]
        ] as [String: Any]
    ]

    private func jsonObject(_ data: Data) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    func testEncodeMatchesJSONSerialization() throws {
        let encoded = try JSONEncoder().encode(KlaviyoAnyCodable(mixed))
        let expected = try JSONSerialization.data(withJSONObject: mixed)
        XCTAssertEqual(try jsonObject(encoded), try jsonObject(expected))
    }

    func testRoundTripPreservesNestedMixedValues() throws {
        let encoded = try JSONEncoder().encode(KlaviyoAnyCodable(mixed))
        let decoded = try JSONDecoder().decode(KlaviyoAnyCodable.self, from: encoded)
        let dict = try XCTUnwrap(decoded.value as? [String: Any])

        XCTAssertEqual(dict["string"] as? String, "hello")
        XCTAssertEqual(dict["int"] as? Int, 42)
        XCTAssertEqual(dict["double"] as? Double, 9.99)
        XCTAssertEqual(dict["bool"] as? Bool, true)
        XCTAssertEqual(dict["nsNumberBool"] as? Bool, false)
        XCTAssertNotNil(dict["null"])
        XCTAssertEqual(decoded, KlaviyoAnyCodable(mixed))

        let nested = try XCTUnwrap(dict["nested"] as? [String: Any])
        let items = try XCTUnwrap(nested["items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["sku"] as? String, "A1")
        let depth = (nested["meta"] as? [String: Any])?["depth"] as? [String: Any]
        XCTAssertEqual(depth?["level"] as? Int, 3)
    }

    func testEventPayloadPropertiesRoundTrip() throws {
        let payload = CreateEventPayload(data: .init(name: "Added To Cart", properties: mixed, anonymousId: "anon"))
        let decoded = try JSONDecoder().decode(
            CreateEventPayload.self,
            from: JSONEncoder().encode(payload)
        )
        XCTAssertEqual(decoded.data.attributes.properties, payload.data.attributes.properties)
    }

    func testProfilePayloadPropertiesRoundTrip() throws {
        let attributes = ProfilePayload.Attributes(properties: mixed, anonymousId: "anon")
        let decoded = try JSONDecoder().decode(
            ProfilePayload.Attributes.self,
            from: JSONEncoder().encode(attributes)
        )
        XCTAssertEqual(decoded.properties, attributes.properties)
    }

    func testAnyEncodableEncodesProfileValues() throws {
        let value = KlaviyoAnyEncodable(["tier": "gold", "points": 120] as [String: Any])
        let encoded = try JSONEncoder().encode(value)
        XCTAssertEqual(try jsonObject(encoded), ["tier": "gold", "points": 120])
    }
}
