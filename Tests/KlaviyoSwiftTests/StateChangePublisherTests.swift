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
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift

@MainActor
final class StateChangePublisherTests: XCTestCase {

    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
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
                return .none
            }
        }
        
        let reducer = KlaviyoTestReducer(reducer: initializationReducer)
        let test = Store(initialState: .test, reducer: reducer)
        environment.analytics.send = {
            test.send($0)
        }
        
        environment.analytics.statePublisher = {
            test.state.eraseToAnyPublisher()
        }
        

        testScheduler.run()
        @MainActor func runDebouncedEffect() {
            _ = environment.analytics.send(.initialize("foo"))
            testScheduler.run()
            // This should not trigger a save since in our reducer it does not change the state.
            _ = environment.analytics.send(.setPushToken("foo"))
            _ = environment.analytics.send(.setEmail("foo"))
        }
        runDebouncedEffect()
        testScheduler.advance(by: .seconds(2.0))
        
        wait(for: [savedCalledExpectation, setEmailSaveExpectation], timeout: 2.0)
        
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
                return .none
            default:
                return .none
            }
        }
        
        let reducer = KlaviyoTestReducer(reducer: initializationReducer)
        let test = Store(initialState: .test, reducer: reducer)
        environment.analytics.send = {
            test.send($0)
        }
        
        environment.analytics.statePublisher = {
            test.state.eraseToAnyPublisher()
        }
        
        @MainActor func runDebouncedEffect() {
            _ = environment.analytics.send(.initialize("foo"))
            _ = environment.analytics.send(.flushQueue)
            _ = environment.analytics.send(.flushQueue)
        }
        
        runDebouncedEffect()

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
                return .none
            }
        }
        
        let reducer = KlaviyoTestReducer(reducer: initializationReducer)
        let test = Store(initialState: .test, reducer: reducer)
        environment.analytics.send = {
            test.send($0)
        }
        
        environment.analytics.statePublisher = {
            test.state.eraseToAnyPublisher()
        }
        _ = environment.analytics.send(.initialize("foo"))
        testScheduler.run()
        for i in 0...10 {
            _ = environment.analytics.send(.setEmail("foo\(i)"))
        }
        testScheduler.advance(by: 1.0)
        wait(for: [savedCalledExpectation], timeout: 1.0)
        
        XCTAssertEqual(count, 2)
    }

}
