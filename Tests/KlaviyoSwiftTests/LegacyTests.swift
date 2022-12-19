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
        
        let legacyEvent = LegacyEvent(eventName: "$opened_push", customerProperties: [
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
    
    //MARK: Legacy request edge cases
    
    func testLegacyEventUnitialized() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.initalizationState = .uninitialized
        
        let legacyEvent = LegacyEvent(eventName: "foo", customerProperties: [
            "$email": "blob@blob.com",
            "$id": "blobid",
            "foo": "bar"
        ], properties: ["baz": "boo"])
        
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        
        _ = await store.send(.enqueueLegacyEvent(legacyEvent))
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
