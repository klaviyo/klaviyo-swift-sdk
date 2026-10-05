//
//  LifecycleStateTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/14/26.
//

@testable import KlaviyoSwift
import Combine
import XCTest

final class LifecycleStateTests: XCTestCase {
    func testTransitionsAndPublisher() {
        let state = LifecycleState()
        var seen: [InitializationState] = []
        let cancellable = state.publisher.sink { seen.append($0) }
        XCTAssertEqual(state.current, .uninitialized)
        XCTAssertTrue(state.beginInitializing())
        XCTAssertEqual(state.current, .initializing)
        XCTAssertFalse(state.beginInitializing()) // idempotent guard
        state.completeInitialization()
        XCTAssertEqual(state.current, .initialized)
        XCTAssertEqual(seen, [.uninitialized, .initializing, .initialized])
        cancellable.cancel()
    }

    func testResetRestoresUninitialized() {
        let state = LifecycleState()
        XCTAssertTrue(state.beginInitializing())
        state.completeInitialization()
        XCTAssertEqual(state.current, .initialized)
        state.reset()
        XCTAssertEqual(state.current, .uninitialized)
        XCTAssertTrue(state.beginInitializing())
    }

    func testCompleteInitializationFromNonInitializingIsNoop() {
        let state = LifecycleState()
        state.completeInitialization()
        XCTAssertEqual(state.current, .uninitialized)
    }
}
