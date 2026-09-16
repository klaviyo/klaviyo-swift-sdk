//
//  RequestBuildingTests.swift
//
//
//  Created by Isobelle Lim on 9/14/26.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

/// Coverage for the builders in `RequestBuilding`. Asserts the builders against the production
/// `RequestFactory` construction path directly.
class RequestBuildingTests: KlaviyoBaseTestCase {
    private let apiKey = "test-api-key"
    private let anonymousId = "test-anon-id"

    // MARK: - requestIdentity

    func testRequestIdentityCarriesAllIdentifiers() {
        let identity = ProfileData(
            email: "a@b.com",
            phoneNumber: "+15005550006",
            externalId: "ext-1",
            anonymousId: anonymousId
        )
        let result = RequestBuilding.requestIdentity(identity, apiKey: apiKey, anonymousId: anonymousId)
        XCTAssertEqual(result, RequestIdentity(
            apiKey: apiKey,
            anonymousId: anonymousId,
            email: "a@b.com",
            phoneNumber: "+15005550006",
            externalId: "ext-1"
        ))
    }

    // MARK: - profilePayload

    func testProfilePayloadReadsIdentifiersFromIdentity() {
        let identity = ProfileData(
            email: "a@b.com",
            phoneNumber: "+15005550006",
            externalId: "ext-1",
            anonymousId: anonymousId
        )
        let profile = Profile.test
        let result = RequestBuilding.profilePayload(
            from: profile,
            identity: identity,
            anonymousId: anonymousId
        )
        let expected = ProfilePayload(
            profile,
            email: identity.email,
            phoneNumber: identity.phoneNumber,
            externalId: identity.externalId,
            anonymousId: anonymousId
        )
        XCTAssertEqual(result, expected)
    }

    // MARK: - resolvedTokenRequest

    func testResolvedTokenRequestMatchesFactory() {
        let identity = ProfileData(
            email: "a@b.com",
            phoneNumber: nil,
            externalId: nil,
            anonymousId: anonymousId
        )
        let result = RequestBuilding.resolvedTokenRequest(
            identity: identity,
            apiKey: apiKey,
            anonymousId: anonymousId,
            pushToken: "tok",
            enablement: .authorized
        )
        let identityProfile = Profile(
            email: identity.email,
            phoneNumber: identity.phoneNumber,
            externalId: identity.externalId
        )
        let expected = RequestFactory.tokenRequest(
            apiKey: apiKey,
            pushToken: "tok",
            enablement: .authorized,
            background: environment.getBackgroundSetting().rawValue,
            profile: ProfilePayload(identityProfile, anonymousId: anonymousId)
        )
        // KlaviyoRequest.== compares id + endpoint. Both ids are the deterministic test UUID
        // (environment.uuid() is stubbed), so this asserts full-request parity including the
        // embedded PushTokenPayload — stronger than endpoint-only comparison.
        XCTAssertEqual(result, expected)
    }

    // MARK: - buildSubscriptionPayload

    func testBuildSubscriptionPayloadBuildsWhenIdentified() {
        let identity = ProfileData(
            email: "a@b.com",
            phoneNumber: "+15005550006",
            externalId: "ext-1",
            anonymousId: anonymousId
        )
        let subscription = Subscription(
            listId: "list-123",
            channels: .init(email: .marketing, sms: .marketing)
        )
        let result = RequestBuilding.buildSubscriptionPayload(
            identity: identity,
            anonymousId: anonymousId,
            subscription: subscription
        )
        XCTAssertNotNil(result, "an identified profile builds a subscription payload")
    }

    func testBuildSubscriptionPayloadNilWhenNoIdentifiers() {
        let identity = ProfileData(anonymousId: anonymousId)
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")
        let result = RequestBuilding.buildSubscriptionPayload(
            identity: identity,
            anonymousId: anonymousId,
            subscription: subscription
        )
        XCTAssertNil(result, "no identifiers → no subscription payload")
    }
}
