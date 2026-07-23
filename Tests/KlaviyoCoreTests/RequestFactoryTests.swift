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
        XCTAssertEqual(payload.data.attributes.properties.value as? [String: Any] != nil, true)
    }
}
