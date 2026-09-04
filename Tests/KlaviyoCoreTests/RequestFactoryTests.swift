//
//  RequestFactoryTests.swift
//
//  Klaviyo Swift SDK
//
//  Created by Belle Lim on 7/23/26.
//

@testable import KlaviyoCore
import AnyCodable
import XCTest

final class RequestFactoryTests: XCTestCase {
    private let identity = RequestIdentity(
        apiKey: "key", anonymousId: "anon",
        email: "a@b.com", phoneNumber: "+15551234567", externalId: "ext-1"
    )

    func testProfileRequestBuildsCreateProfileEndpoint() {
        let request = RequestFactory.profileRequest(identity: identity, properties: ["k": "v"])
        guard case let .createProfile(apiKey, payload) = request.endpoint else {
            return XCTFail("expected createProfile")
        }
        XCTAssertEqual(apiKey, "key")
        XCTAssertEqual(payload.data.attributes.email, "a@b.com")
        XCTAssertEqual(payload.data.attributes.phoneNumber, "+15551234567")
        XCTAssertEqual(payload.data.attributes.externalId, "ext-1")
        XCTAssertEqual(payload.data.attributes.anonymousId, "anon")
    }

    func testUnregisterRequestBuildsEndpoint() {
        let request = RequestFactory.unregisterRequest(identity: identity, pushToken: "tok")
        guard case let .unregisterPushToken(apiKey, payload) = request.endpoint else {
            return XCTFail("expected unregisterPushToken")
        }
        XCTAssertEqual(apiKey, "key")
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, "anon")
        XCTAssertEqual(payload.data.attributes.token, "tok")
    }

    func testTokenRequestBuildsEndpoint() {
        let profile = ProfilePayload(anonymousId: "anon")
        let request = RequestFactory.tokenRequest(
            apiKey: "key", pushToken: "tok",
            enablement: .authorized, background: PushBackground.available.rawValue,
            profile: profile
        )
        guard case let .registerPushToken(apiKey, payload) = request.endpoint else {
            return XCTFail("expected registerPushToken")
        }
        XCTAssertEqual(apiKey, "key")
        XCTAssertEqual(payload.data.attributes.token, "tok")
        XCTAssertEqual(payload.data.attributes.enablementStatus, PushEnablement.authorized.rawValue)
        XCTAssertEqual(payload.data.attributes.backgroundStatus, PushBackground.available.rawValue)
    }

    func testEventRequestStampsIdentifiers() {
        let event = Event(name: ._openedPush)
        let request = RequestFactory.eventRequest(identity: identity, event: event, pushToken: "tok")
        guard case let .createEvent(apiKey, payload) = request.endpoint else {
            return XCTFail("expected createEvent")
        }
        XCTAssertEqual(apiKey, "key")
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.email, "a@b.com")
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, "anon")
        let props = payload.data.attributes.properties.value as? [String: Any]
        XCTAssertEqual(props?["Push Token"] as? String, "tok")
    }

    // MARK: - apiKey-free payload builders

    func testEventPayloadMatchesEventRequestPayload() {
        let event = Event(name: .customEvent("X"), properties: ["k": "v"])

        let viaRequest = RequestFactory.eventRequest(identity: identity, event: event, pushToken: "tok")
        let payload = RequestFactory.eventPayload(
            identity: PayloadIdentity(identity), event: event, pushToken: "tok"
        )

        guard case let .createEvent(_, requestPayload) = viaRequest.endpoint else {
            return XCTFail("expected createEvent endpoint")
        }
        XCTAssertEqual(payload, requestPayload)
    }

    func testTokenPayloadMatchesTokenRequestPayload() {
        let payloadIdentity = PayloadIdentity(anonymousId: "anon")
        let profile = ProfilePayload(anonymousId: "anon")
        let viaRequest = RequestFactory.tokenRequest(
            apiKey: "pk", pushToken: "tok", enablement: .authorized,
            background: PushBackground.available.rawValue, profile: profile
        )
        let payload = RequestFactory.tokenPayload(
            identity: payloadIdentity, pushToken: "tok",
            enablement: .authorized, background: .available
        )

        guard case let .registerPushToken(_, requestPayload) = viaRequest.endpoint else {
            return XCTFail("expected registerPushToken endpoint")
        }
        XCTAssertEqual(payload, requestPayload)
    }

    func testProfilePayloadRequestIdentityOverloadDelegates() {
        let properties: [String: Any] = ["foo": "bar"]

        let viaRequestIdentity = RequestFactory.profilePayload(identity: identity, properties: properties)
        let viaPayloadIdentity = RequestFactory.profilePayload(
            identity: PayloadIdentity(identity), properties: properties
        )

        XCTAssertEqual(viaRequestIdentity, viaPayloadIdentity)
    }

    func testTokenPayloadWithProfileEmbedsGivenProfile() {
        let profile = ProfilePayload(
            email: "b@example.com", phoneNumber: nil, externalId: "user-B",
            properties: [:], anonymousId: "anon-B"
        )
        let payload = RequestFactory.tokenPayload(
            pushToken: "tok-1", enablement: .authorized,
            background: .available, profile: profile
        )
        XCTAssertEqual(payload.data.attributes.token, "tok-1")
        XCTAssertEqual(payload.data.attributes.enablementStatus, PushEnablement.authorized.rawValue)
        XCTAssertEqual(payload.data.attributes.backgroundStatus, PushBackground.available.rawValue)
        XCTAssertEqual(payload.data.attributes.profile.data, profile)
    }
}
