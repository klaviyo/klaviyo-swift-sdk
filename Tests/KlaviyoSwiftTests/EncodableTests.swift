//
//  EncodableTests.swift
//
//
//  Created by Noah Durell on 11/14/22.
//

@testable import KlaviyoSwift
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
        let profile = Profile.test
        let payload = CreateProfilePayload(data: profile.toAPIModel(anonymousId: "foo"))
        assertSnapshot(matching: payload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testEventPayloadWithoutMetadata() throws {
        let event = Event.test
        let createEventPayload = CreateEventPayload(data: CreateEventPayload.Event(name: event.metric.name.value, anonymousId: "anon-id"))
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

    func testKlaviyoState() throws {
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo"))
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(tokenPayload))
        let klaviyoState = KlaviyoState(
            email: "foo",
            anonymousId: "foo",
            phoneNumber: "foo",
            pushTokenData: .init(
                pushToken: "foo",
                pushEnablement: .authorized,
                pushBackground: .available,
                deviceData: .init(context: environment.appContextInfo())),
            queue: [request],
            requestsInFlight: [request])
        assertSnapshot(matching: klaviyoState, as: .json)
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
