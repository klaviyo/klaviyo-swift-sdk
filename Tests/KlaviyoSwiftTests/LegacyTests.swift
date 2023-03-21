//
//  LegacyTests.swift
//  Tests for legacy apis and legacy handling.
//
//  Created by Noah Durell on 12/15/22.
//

@testable import KlaviyoSwift
import Foundation
import XCTest

@MainActor
class LegacyTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }

    func testLegacyProfileRequestSetsEmail() async throws {
        let initialState = INITIALIZED_TEST_STATE()

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueLegacyProfile(LEGACY_PROFILE)) {
            $0.email = "blob@blob.com"
            guard let request = try LEGACY_PROFILE.buildProfileRequest(with: initialState.apiKey!, from: $0) else {
                XCTFail()
                return
            }
            $0.queue = [request]
        }
    }

    func testLegacyEventRequestSetsIdentifiers() async throws {
        let initialState = INITIALIZED_TEST_STATE()

        let legacyEvent = LegacyEvent(eventName: "foo", customerProperties: [
            "$email": "blob@blob.com",
            "$id": "blobid",
            "foo": "bar"
        ], properties: ["baz": "boo"])

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueLegacyEvent(legacyEvent)) {
            $0.email = "blob@blob.com"
            $0.externalId = "blobid"
            guard let request = try legacyEvent.buildEventRequest(with: initialState.apiKey!, from: $0) else {
                XCTFail()
                return
            }
            $0.queue = [request]
        }
    }

    func testLegacyEventOpenedPush() async throws {
        let initialState = INITIALIZED_TEST_STATE()

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueLegacyEvent(LEGACY_OPENED_PUSH)) {
            $0.email = "blob@blob.com"
            $0.externalId = "blobid"
            guard let request = try LEGACY_OPENED_PUSH.buildEventRequest(with: initialState.apiKey!, from: $0) else {
                XCTFail()
                return
            }
            $0.queue = [request]
        }
    }

    // MARK: Pending Events

    func testLegacyEventsAndProfilesAreLoggedAfterInitialization() async throws {
        let pendingRequests: [KlaviyoState.PendingRequest] = [.legacyEvent(LEGACY_OPENED_PUSH), .legacyProfile(LEGACY_PROFILE)]
        let initialState = KlaviyoState(queue: [], pendingRequests: pendingRequests)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Avoids a warning in xcode despite the result being discardable.
        _ = await store.send(.initialize(TEST_API_KEY)) {
            $0.apiKey = TEST_API_KEY
            $0.initalizationState = .initializing
        }

        let expectedState = KlaviyoState(apiKey: TEST_API_KEY, anonymousId: environment.analytics.uuid().uuidString, queue: [], requestsInFlight: [], pendingRequests: pendingRequests)
        let profileRequest = try expectedState.buildProfileRequest()
        await store.receive(.completeInitialization(expectedState)) {
            $0.anonymousId = expectedState.anonymousId
            $0.initalizationState = .initialized
            $0.queue = [profileRequest]
            $0.pendingRequests = []
        }

        await store.receive(.enqueueLegacyEvent(LEGACY_OPENED_PUSH)) {
            $0.email = "blob@blob.com"
            $0.externalId = "blobid"
            guard let openedPushRequest = try LEGACY_OPENED_PUSH.buildEventRequest(with: TEST_API_KEY, from: $0) else {
                XCTFail()
                return
            }
            $0.queue = [profileRequest, openedPushRequest]
        }

        await store.receive(.enqueueLegacyProfile(LEGACY_PROFILE)) {
            guard let openedPushRequest = try LEGACY_OPENED_PUSH.buildEventRequest(with: TEST_API_KEY, from: $0) else {
                XCTFail()
                return
            }
            let secondProfile = try! LEGACY_PROFILE.buildProfileRequest(with: TEST_API_KEY, from: $0)!
            $0.email = "blob@blob.com"
            $0.externalId = "blobid"
            $0.queue = [profileRequest, openedPushRequest, secondProfile]
        }
        await store.receive(.start)

        await store.receive(.flushQueue) {
            $0.flushing = true
            $0.queue = []
            guard let openedPushRequest = try LEGACY_OPENED_PUSH.buildEventRequest(with: TEST_API_KEY, from: $0) else {
                XCTFail()
                return
            }
            let secondProfile = try! LEGACY_PROFILE.buildProfileRequest(with: TEST_API_KEY, from: $0)!
            $0.requestsInFlight = [profileRequest, openedPushRequest, secondProfile]
        }
        await store.receive(.sendRequest)
        await store.receive(.dequeCompletedResults(profileRequest)) {
            $0.flushing = false
            $0.requestsInFlight = []
        }
    }

    // MARK: Legacy request edge cases

    func testLegacyEventUnitialized() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.initalizationState = .uninitialized

        let legacyEvent = LegacyEvent(eventName: "foo", customerProperties: [
            "$email": "blob@blob.com",
            "$id": "blobid",
            "foo": "bar"
        ], properties: ["baz": "boo"])

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueLegacyEvent(legacyEvent)) {
            $0.pendingRequests = [.legacyEvent(legacyEvent)]
        }
    }

    func testLegacyProfileUnitializedUpdatesPendingProfiles() async throws {
        let apiKey = "foo"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: true)

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueLegacyProfile(LEGACY_PROFILE)) {
            $0.pendingRequests = [.legacyProfile(LEGACY_PROFILE)]
        }
    }

    func testInvalidLegacyEventCustomerPropertiesHasNoEffect() async throws {
        let initialState = INITIALIZED_TEST_STATE()

        let legacyEvent = LegacyEvent(eventName: "foo", customerProperties: [
            1: "blob@blob.com",
            "$id": "blobid",
            "foo": "bar"
        ], properties: ["baz": "boo"])

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueLegacyEvent(legacyEvent))
    }

    func testInvalidLegacyEventPropertiesStillUpdatesState() async throws {
        // Interesting edge case maybe...we are updating the state even the payload is invalid.
        // This is potentially ok though since the identifiers is still valid
        let initialState = INITIALIZED_TEST_STATE()

        let legacyEvent = LegacyEvent(eventName: "foo", customerProperties: [
            "$email": "blob@blob.com",
            "$id": "blobid",
            "foo": "bar"
        ], properties: [1: "boo"])

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueLegacyEvent(legacyEvent)) {
            $0.email = "blob@blob.com"
            $0.externalId = "blobid"
        }
    }

    func testInvalidLegacyProfileDoesntUpdateState() async throws {
        let initialState = INITIALIZED_TEST_STATE()

        let legacyProfile = LegacyProfile(customerProperties: [
            "$email": "blob@blob.com",
            "$id": "blobid",
            1: "bar"
        ])

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueLegacyProfile(legacyProfile))
    }

    func testLegacyProfileMissingAnonymousId() async throws {
        // Ideally not possible but testing for coverage
        var initialState = INITIALIZED_TEST_STATE()
        initialState.anonymousId = nil

        let legacyProfile = LegacyProfile(customerProperties: [
            "$email": "blob@blob.com",
            "$id": "blobid",
            "foo": "bar"
        ])

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueLegacyProfile(legacyProfile)) {
            $0.email = "blob@blob.com"
            $0.externalId = "blobid"
        }
    }
}
