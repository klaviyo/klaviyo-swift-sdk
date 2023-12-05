//
//  EncodableTests.swift
//
//
//  Created by Noah Durell on 11/14/22.
//

@testable import KlaviyoSwift
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
        let data = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload.Profile(profile: profile, anonymousId: "foo")
        let payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload(data: data)
        assertSnapshot(matching: payload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testEventPayloadWithoutMetadata() throws {
        let event = Event.test
        let createEventPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload(data: .init(event: event, anonymousId: "anon-id"))
        assertSnapshot(matching: createEventPayload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testEventPayloadWithMetadata() throws {
        let event = Event.test
        var createEventPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload(data: .init(event: event, anonymousId: "anon-id"))
        createEventPayload.appendMetadataToProperties()
        assertSnapshot(matching: createEventPayload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testTokenPayload() throws {
        let tokenPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: .init(email: "foo", phoneNumber: "foo"),
            anonymousId: "foo")
        assertSnapshot(matching: tokenPayload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testUnregisterTokenPayload() throws {
        let tokenPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.UnregisterPushTokenPayload(
            pushToken: "foo",
            profile: .init(email: "foo", phoneNumber: "foo"),
            anonymousId: "foo")
        assertSnapshot(matching: tokenPayload, as: .json)
    }

    func testKlaviyoState() throws {
        let tokenPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: .init(email: "foo", phoneNumber: "foo"),
            anonymousId: "foo")
        let request = KlaviyoAPI.KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(tokenPayload))
        let klaviyoState = KlaviyoState(email: "foo", anonymousId: "foo",
                                        phoneNumber: "foo", pushTokenData: .init(pushToken: "foo", pushEnablement: .authorized, pushBackground: .available, deviceData: .init(context: environment.analytics.appContextInfo())),
                                        queue: [request], requestsInFlight: [request])
        assertSnapshot(matching: klaviyoState, as: .json)
    }

    func testKlaviyoRequest() throws {
        let tokenPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: .init(email: "foo", phoneNumber: "foo"),
            anonymousId: "foo")
        let request = KlaviyoAPI.KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(tokenPayload))
        assertSnapshot(matching: request, as: .json)
    }
}
