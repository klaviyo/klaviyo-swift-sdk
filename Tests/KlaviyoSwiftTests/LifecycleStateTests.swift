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
        let s = LifecycleState()
        var seen: [InitializationState] = []
        let c = s.publisher.sink { seen.append($0) }
        XCTAssertEqual(s.current, .uninitialized)
        XCTAssertTrue(s.beginInitializing())
        XCTAssertEqual(s.current, .initializing)
        XCTAssertFalse(s.beginInitializing()) // idempotent guard
        s.completeInitialization()
        XCTAssertEqual(s.current, .initialized)
        XCTAssertEqual(seen, [.uninitialized, .initializing, .initialized])
        c.cancel()
    }

    func testResetRestoresUninitialized() {
        let s = LifecycleState()
        XCTAssertTrue(s.beginInitializing())
        s.completeInitialization()
        XCTAssertEqual(s.current, .initialized)
        s.reset()
        XCTAssertEqual(s.current, .uninitialized)
        XCTAssertTrue(s.beginInitializing())
    }

    func testCompleteInitializationFromNonInitializingIsNoop() {
        let s = LifecycleState()
        s.completeInitialization()
        XCTAssertEqual(s.current, .uninitialized)
    }

    func testSharedInstanceExists() {
        XCTAssertNotNil(LifecycleState.shared)
    }
}
