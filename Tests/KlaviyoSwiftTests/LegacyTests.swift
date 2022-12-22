//
//  LegacyTests.swift
//  Tests for legacy apis and legacy handling.
//
//  Created by Noah Durell on 12/15/22.
//

import Foundation
import XCTest
@testable import KlaviyoSwift

@MainActor
class LegacyTests: XCTestCase {
    
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }
    
    func testLegacyProfileRequestSetsEmail() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        
        let legacyProfile = LegacyProfile(customerProperties: [
            "$email": "blob@blob.com",
            "foo": "bar"
        ])
        
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        
        _ = await store.send(.enqueueLegacyProfile(legacyProfile)) {
            $0.email = "blob@blob.com"
            guard let request = try legacyProfile.buildProfileRequest(with: initialState.apiKey!, from: $0) else {
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
    
    func testLegacyEventsAreLoggedAfterInitialization() async throws {
        let initialState = KlaviyoState(queue: [], pendingLegacyEvents: [LEGACY_OPENED_PUSH])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        
        let apiKey = "fake-key"
        // Avoids a warning in xcode despite the result being discardable.
        _ = await store.send(.initialize(apiKey)) {
            $0.apiKey = apiKey
            $0.initalizationState = .initializing
        }
        
        let expectedState = KlaviyoState(apiKey: apiKey, anonymousId: environment.analytics.uuid().uuidString, queue: [], requestsInFlight: [], pendingLegacyEvents: [LEGACY_OPENED_PUSH])
        let profileRequest = try expectedState.buildProfileRequest()
        await store.receive(.completeInitialization(expectedState)) {
            $0.anonymousId = expectedState.anonymousId
            $0.initalizationState = .initialized
            $0.queue = [profileRequest]
            $0.pendingLegacyEvents = []
        }
        
        await store.receive(.enqueueLegacyEvent(LEGACY_OPENED_PUSH)) {
            $0.email = "blob@blob.com"
            $0.externalId = "blobid"
            guard let openedPushRequest = try LEGACY_OPENED_PUSH.buildEventRequest(with: apiKey, from: $0) else {
                XCTFail()
                return
            }
            $0.queue = [profileRequest, openedPushRequest]
        }
        
        await store.receive(.start)
        
        await store.receive(.flushQueue) {
            guard let openedPushRequest = try LEGACY_OPENED_PUSH.buildEventRequest(with: apiKey, from: $0) else {
                XCTFail()
                return
            }
            $0.flushing = true
            $0.queue = []
            $0.requestsInFlight = [profileRequest, openedPushRequest]
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
            $0.pendingLegacyEvents = [legacyEvent]
        }
    }
    
    func testLegacyProfileUnitialized() async throws {
        let apiKey = "foo"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: true)
        
        let legacyProfile = LegacyProfile(customerProperties: [
            "$email": "blob@blob.com",
            "foo": "bar"
        ])
        
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        
        _ = await store.send(.enqueueLegacyProfile(legacyProfile))
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
