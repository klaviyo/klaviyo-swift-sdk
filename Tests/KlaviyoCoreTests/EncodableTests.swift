//
//  EncodableTests.swift
//
//
//  Created by Noah Durell on 11/14/22.
//

import KlaviyoCore
import SnapshotTesting
import XCTest

final class EncodableTests: XCTestCase {
    let testEncoder = KlaviyoEnvironment.encoder

    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        testEncoder.outputFormatting = .prettyPrinted.union(.sortedKeys)
    }

    func testProfilePayload() throws {
        let payload = CreateProfilePayload(data: .test)
        assertSnapshot(matching: payload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testEventPayload() throws {
        let payloadData = CreateEventPayload.Event(name: "test", properties: SAMPLE_PROPERTIES, anonymousId: "anon-id")
        let createEventPayload = CreateEventPayload(data: payloadData)
        assertSnapshot(matching: createEventPayload, as: .json(KlaviyoEnvironment.encoder))
    }

    /// Encodes a `CreateEventPayload` and returns its `data.attributes` object.
    private func encodedEventAttributes(value: Double? = nil, valueCurrency: String? = nil) throws -> [String: Any] {
        let payload = CreateEventPayload(data: CreateEventPayload.Event(
            name: "test",
            anonymousId: "anon-id",
            value: value,
            valueCurrency: valueCurrency
        ))
        let json = try JSONSerialization.jsonObject(with: testEncoder.encode(payload))
        let root = try XCTUnwrap(json as? [String: Any])
        let data = try XCTUnwrap(root["data"] as? [String: Any])
        return try XCTUnwrap(data["attributes"] as? [String: Any])
    }

    func testEventPayloadOmitsValueCurrencyWhenNil() throws {
        let attributes = try encodedEventAttributes()
        XCTAssertNil(attributes["value_currency"])
        XCTAssertNil(attributes["valueCurrency"])
        XCTAssertNil(attributes["value"])
    }

    func testEventPayloadEncodesValueCurrency() throws {
        let attributes = try encodedEventAttributes(value: 9.99, valueCurrency: "USD")
        XCTAssertEqual(attributes["value"] as? Double, 9.99)
        XCTAssertEqual(attributes["value_currency"] as? String, "USD")
    }

    func testTokenPayload() throws {
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo")
        )
        assertSnapshot(matching: tokenPayload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testUnregisterTokenPayload() throws {
        let tokenPayload = UnregisterPushTokenPayload(
            pushToken: "foo",
            email: "foo",
            phoneNumber: "foo",
            anonymousId: "foo"
        )
        assertSnapshot(matching: tokenPayload, as: .json)
    }

    func testKlaviyoRequest() throws {
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo")
        )
        let request = KlaviyoRequest(endpoint: .registerPushToken("foo", tokenPayload))
        assertSnapshot(matching: request, as: .json)
    }
}
