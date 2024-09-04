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
        let SAMPLE_PROPERTIES = [
            "blob": "blob",
            "stuff": 2,
            "hello": [
                "sub": "dict"
            ]
        ] as [String: Any]
        let payloadData = CreateEventPayload.Event(name: "test", properties: SAMPLE_PROPERTIES, anonymousId: "anon-id")
        let createEventPayload = CreateEventPayload(data: payloadData)
        assertSnapshot(matching: createEventPayload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testTokenPayload() throws {
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo"))
        assertSnapshot(matching: tokenPayload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testUnregisterTokenPayload() throws {
        let tokenPayload = UnregisterPushTokenPayload(
            pushToken: "foo",
            email: "foo",
            phoneNumber: "foo",
            anonymousId: "foo")
        assertSnapshot(matching: tokenPayload, as: .json)
    }

    func testKlaviyoRequest() throws {
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo"))
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(tokenPayload))
        assertSnapshot(matching: request, as: .json)
    }
}
