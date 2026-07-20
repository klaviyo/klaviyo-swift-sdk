//
//  StateChangePublisherTests.swift
//
//
//  Created by Noah Durell on 12/21/22.
//

import Combine
import CombineSchedulers
import Foundation
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import KlaviyoCore

final class StateChangePublisherTests: XCTestCase {
    @MainActor
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
    }

    @MainActor
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
        let testScheduler = DispatchQueue.test
        StateChangePublisher.debouncedPublisher = { publisher in
            publisher
                .debounce(for: .seconds(1), scheduler: testScheduler)
                .eraseToAnyPublisher()
        }
        let initializationReducer = { (state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> in
            switch action {
            case .initialize:
                state.initalizationState = .initialized
                return StateChangePublisher().publisher().eraseToEffect()
            case let .setEmail(email):
                state.email = email
                return .none
            default:
                return .none
            }
        }

        let reducer = KlaviyoTestReducer(reducer: initializationReducer)
        let test = Store(initialState: .test, reducer: reducer)
        klaviyoSwiftEnvironment.send = {
            test.send($0)
        }

        klaviyoSwiftEnvironment.statePublisher = {
            test.state.eraseToAnyPublisher()
        }

        testScheduler.run()
        @MainActor
        func runDebouncedEffect() {
            _ = klaviyoSwiftEnvironment.send(.initialize("foo"))
            testScheduler.run()
            // This should not trigger a save since in our reducer it does not change the state.
            _ = klaviyoSwiftEnvironment.send(.setPushToken("foo", .authorized))
            _ = klaviyoSwiftEnvironment.send(.setEmail("foo"))
        }
        runDebouncedEffect()
        testScheduler.advance(by: .seconds(2.0))

        wait(for: [savedCalledExpectation, setEmailSaveExpectation], timeout: 2.0)

        XCTAssertEqual(count, 2)
    }

    @MainActor
    func testStateChangeDuplicateAreRemoved() throws {
        let savedCalledExpectation = XCTestExpectation(description: "Save called on initialization")
        savedCalledExpectation.assertForOverFulfill = true

        environment.fileClient.write = { _, _ in
            savedCalledExpectation.fulfill()
        }
        let initializationReducer = { (state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> in
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
        klaviyoSwiftEnvironment.send = {
            test.send($0)
        }

        klaviyoSwiftEnvironment.statePublisher = {
            test.state.eraseToAnyPublisher()
        }

        @MainActor
        func runDebouncedEffect() {
            _ = klaviyoSwiftEnvironment.send(.initialize("foo"))
            _ = klaviyoSwiftEnvironment.send(.flushQueue)
            _ = klaviyoSwiftEnvironment.send(.flushQueue)
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

        let testScheduler = DispatchQueue.test
        StateChangePublisher.debouncedPublisher = { publisher in
            publisher
                .debounce(for: .seconds(1), scheduler: testScheduler)
                .eraseToAnyPublisher()
        }
        let initializationReducer = { (state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> in
            switch action {
            case .initialize:
                state.initalizationState = .initialized
                return StateChangePublisher().publisher().eraseToEffect()
            case let .setEmail(email):
                state.email = email
                return .none
            default:
                return .none
            }
        }

        let reducer = KlaviyoTestReducer(reducer: initializationReducer)
        let test = Store(initialState: .test, reducer: reducer)
        klaviyoSwiftEnvironment.send = {
            test.send($0)
        }

        klaviyoSwiftEnvironment.statePublisher = {
            test.state.eraseToAnyPublisher()
        }
        _ = klaviyoSwiftEnvironment.send(.initialize("foo"))
        testScheduler.run()
        for i in 0...10 {
            _ = klaviyoSwiftEnvironment.send(.setEmail("foo\(i)"))
        }
        testScheduler.advance(by: 1.0)
        wait(for: [savedCalledExpectation], timeout: 1.0)

        XCTAssertEqual(count, 2)
    }
}
