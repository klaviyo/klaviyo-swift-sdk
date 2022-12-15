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
        let apiKey = "foo"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        pushToken: "blob_token",
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        
        let legacyProfile = LegacyProfile(customerProperties: [
            "$email": "blob@blob.com",
            "foo": "bar"
        ])
        
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        
        _ = await store.send(.enqueueLegacyProfile(legacyProfile)) {
            $0.email = "blob@blob.com"
            guard let request = try legacyProfile.buildProfileRequest(with: apiKey, from: $0) else {
                XCTFail()
                return
            }
            $0.queue = [request]
        }
        
    }
    
    func testLegacyEventRequestSetsIdentifiers() async throws {
        let apiKey = "foo"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        pushToken: "blob_token",
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        
        let legacyEvent = LegacyEvent(eventName: "foo", customerProperties: [
            "$email": "blob@blob.com",
            "$id": "blobid",
            "foo": "bar"
        ], properties: ["baz": "boo"])
        
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        
        _ = await store.send(.enqueueLegacyEvent(legacyEvent)) {
            $0.email = "blob@blob.com"
            $0.externalId = "blobid"
            guard let request = try legacyEvent.buildEventRequest(with: apiKey, from: $0) else {
                XCTFail()
                return
            }
            $0.queue = [request]
        }
        
    }
    
    func testLegacyEventOpenedPush() async throws {
        let apiKey = "foo"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        pushToken: "blob_token",
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        
        let legacyEvent = LegacyEvent(eventName: "$opened_push", customerProperties: [
            "$email": "blob@blob.com",
            "$id": "blobid",
            "foo": "bar"
        ], properties: ["baz": "boo"])
        
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        
        _ = await store.send(.enqueueLegacyEvent(legacyEvent)) {
            $0.email = "blob@blob.com"
            $0.externalId = "blobid"
            guard let request = try legacyEvent.buildEventRequest(with: apiKey, from: $0) else {
                XCTFail()
                return
            }
            $0.queue = [request]
        }
        
    }
    
    func testLegacyEventUnitialized() async throws {
        let apiKey = "foo"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: true)
        
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
}
