//
//  RequestBuildingTests.swift
//
//
//  Created by Isobelle Lim on 9/14/26.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

/// Parity tests: each free function in `RequestBuilding.swift` must produce the same output as the
/// corresponding `KlaviyoState` method for identical inputs.
class RequestBuildingTests: StateManagementTestCase {
    private let apiKey = "test-api-key"
    private let anonymousId = "test-anon-id"

    // MARK: - requestIdentity

    func testRequestIdentityMatchesLegacy() {
        let identity = ProfileData(
            email: "a@b.com",
            phoneNumber: "+15005550006",
            externalId: "ext-1",
            anonymousId: anonymousId
        )
        let newResult = requestIdentity(identity, apiKey: apiKey, anonymousId: anonymousId)
        var legacyState = KlaviyoState(apiKey: apiKey, anonymousId: anonymousId)
        legacyState.identity = identity
        let legacyResult = legacyState.requestIdentity(apiKey: apiKey, anonymousId: anonymousId)
        XCTAssertEqual(newResult, legacyResult)
    }

    // MARK: - profilePayload

    func testProfilePayloadMatchesLegacy() {
        let identity = ProfileData(
            email: "a@b.com",
            phoneNumber: "+15005550006",
            externalId: "ext-1",
            anonymousId: anonymousId
        )
        let profile = Profile.test
        let newResult = profilePayload(from: profile, identity: identity, anonymousId: anonymousId)
        var legacyState = KlaviyoState(apiKey: apiKey, anonymousId: anonymousId)
        legacyState.identity = identity
        let legacyResult = legacyState.profilePayload(from: profile, anonymousId: anonymousId)
        XCTAssertEqual(newResult, legacyResult)
    }

    // MARK: - resolvedTokenRequest

    func testResolvedTokenRequestMatchesLegacy() {
        let identity = ProfileData(
            email: "a@b.com",
            phoneNumber: nil,
            externalId: nil,
            anonymousId: anonymousId
        )
        let newResult = resolvedTokenRequest(
            identity: identity,
            apiKey: apiKey,
            anonymousId: anonymousId,
            pushToken: "tok",
            enablement: .authorized
        )
        var legacyState = KlaviyoState(apiKey: apiKey, email: "a@b.com", anonymousId: anonymousId)
        legacyState.identity = identity
        let legacyResult = legacyState.resolvedTokenRequest(
            apiKey: apiKey,
            anonymousId: anonymousId,
            pushToken: "tok",
            enablement: .authorized
        )
        // KlaviyoRequest.== compares id + endpoint. Both ids are the deterministic test UUID
        // (environment.uuid() is stubbed), so this asserts full-request parity including the
        // embedded PushTokenPayload — stronger than endpoint-only comparison.
        XCTAssertEqual(newResult, legacyResult)
    }

    // MARK: - buildSubscriptionPayload

    func testBuildSubscriptionPayloadMatchesLegacy() {
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
        let newResult = buildSubscriptionPayload(
            identity: identity,
            anonymousId: anonymousId,
            subscription: subscription
        )
        var legacyState = KlaviyoState(apiKey: apiKey, anonymousId: anonymousId)
        legacyState.identity = identity
        let legacyResult = legacyState.buildSubscriptionPayload(
            anonymousId: anonymousId,
            subscription: subscription
        )
        XCTAssertEqual(newResult, legacyResult)
    }

    func testBuildSubscriptionPayloadNilWhenNoIdentifiers() {
        let identity = ProfileData(anonymousId: anonymousId)
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")
        let result = buildSubscriptionPayload(
            identity: identity,
            anonymousId: anonymousId,
            subscription: subscription
        )
        var legacyState = KlaviyoState(apiKey: apiKey, anonymousId: anonymousId)
        legacyState.identity = identity
        let legacyResult = legacyState.buildSubscriptionPayload(
            anonymousId: anonymousId,
            subscription: subscription
        )
        XCTAssertNil(result)
        XCTAssertEqual(result, legacyResult)
    }
}
