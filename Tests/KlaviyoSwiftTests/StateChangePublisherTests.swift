//
//  StateChangePublisherTests.swift
//  
//
//  Created by Noah Durell on 12/21/22.
//

import Foundation
import XCTest
import Combine
import CombineSchedulers
@testable import KlaviyoSwift

@MainActor
final class StateChangePublisherTests: XCTestCase {
    
    func testReducer( state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> {
        return .none
    }

    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testStateChangePublisher() throws {
        let savedCalledExpectation = XCTestExpectation(description: "Save called on initialization")
        // Third call set email should trigger again
        let setEmailSaveExpectation = XCTestExpectation(description: "Set email should be saved.")
        
        var count = 0
        environment.fileClient.write = { _, _ in
            if count == 0 {
                savedCalledExpectation.fulfill()
            } else if count == 1 {
                setEmailSaveExpectation.fulfill()
            }
            count += 1
        }
        let initializationReducer = { ( state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> in
            switch action {
            case .initialize:
                state.initalizationState = .initialized
                return StateChangePublisher().publisher().eraseToEffect()
            case .setEmail(let email):
                state.email = email
                return .none
            default:
                state = state
            }
            return .none
        }
        
        let reducer = KlaviyoTestReducer(reducer: initializationReducer)
        let test = Store(initialState: .test, reducer: reducer)
        environment.analytics.store = test
        _ = environment.analytics.store.send(.initialize("foo"))
        // This should not trigger a save since in our reducer it does not change the state.
        _ = environment.analytics.store.send(.setPushToken("foo"))
        _ = environment.analytics.store.send(.setEmail("foo"))
        
        wait(for: [savedCalledExpectation, setEmailSaveExpectation], timeout: 1.0)
        
        XCTAssertEqual(count, 2)
    }
    
    func testStateChangeDuplicateAreRemoved() throws {
        let savedCalledExpectation = XCTestExpectation(description: "Save called on initialization")
        savedCalledExpectation.assertForOverFulfill = true
        
        environment.fileClient.write = { _, _ in
            savedCalledExpectation.fulfill()
        }
        let initializationReducer = { ( state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> in
            switch action {
            case .initialize:
                state.initalizationState = .initialized
                return StateChangePublisher.test.publisher().eraseToEffect()
            case .flushQueue:
                state = state
            default:
                state = state
            }
            return .none
        }
        
        let reducer = KlaviyoTestReducer(reducer: initializationReducer)
        let test = Store(initialState: .test, reducer: reducer)
        environment.analytics.store = test
        _ = environment.analytics.store.send(.initialize("foo"))
        _ = environment.analytics.store.send(.flushQueue)
        _ = environment.analytics.store.send(.flushQueue)
        
        wait(for: [savedCalledExpectation], timeout: 1.0)
    }
    
    func testQuickStateUpdatesTriggerOnlyOneSaves() throws {
        let savedCalledExpectation = XCTestExpectation(description: "Save called on initialization")
        var count = 0
        environment.fileClient.write = { _, _ in
            if count == 1 {
                savedCalledExpectation.fulfill()
            }
            count += 1
        }

        let testScheduler =  DispatchQueue.test
        StateChangePublisher.debouncedPublisher = { publisher in
            publisher
                .debounce(for: .seconds(1), scheduler: testScheduler)
                .eraseToAnyPublisher()
        }
        let initializationReducer = { ( state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> in
            switch action {
            case .initialize:
                state.initalizationState = .initialized
                return StateChangePublisher().publisher().eraseToEffect()
            case .setEmail(let email):
                state.email = email
                return .none
            default:
                state = state
            }
            return .none
        }
        
        let reducer = KlaviyoTestReducer(reducer: initializationReducer)
        let test = Store(initialState: .test, reducer: reducer)
        environment.analytics.store = test
        _ = environment.analytics.store.send(.initialize("foo"))
        testScheduler.run()
        for i in 0...10 {
            _ = environment.analytics.store.send(.setEmail("foo\(i)"))
        }
        testScheduler.advance(by: 1.0)
        wait(for: [savedCalledExpectation], timeout: 1.0)
        
        XCTAssertEqual(count, 2)
    }

}
