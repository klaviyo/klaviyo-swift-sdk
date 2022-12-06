//
//  StateManagementTests.swift
//  
//
//  Created by Noah Durell on 12/6/22.
//

import Foundation
import XCTest
@testable import KlaviyoSwift


@MainActor
class StateManagementTests: XCTestCase {
    
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test
    }
    
    func testInitialize() async {
        let store = TestStore(initialState: KlaviyoState(queue: [], requestsInFlight: []), reducer: StateManagement().reduce(state:action:))
        
        let apiKey = "fake-key"
        await store.send(.initialize(apiKey)) {
            $0.apiKey = apiKey
        }
        
        let expectedState = KlaviyoState(apiKey: apiKey, queue: [], requestsInFlight: [])
        await store.receive(.completeInitialization(expectedState)) {
            $0 = expectedState
        }
    }
    
}
