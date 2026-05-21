//
//  DispatchOnMainThreadTests.swift
//  KlaviyoSwiftTests
//
//  Coverage for the `dispatchOnMainThread(_:)` closure overload used by both
//  `KlaviyoSDK.handle(...)` and `KlaviyoNotificationDelegate.OnceCallback`. The helper
//  enforces the main-thread invariant required by `UNUserNotificationCenter` completion
//  handlers (which touch `UIApplication` state-restoration bookkeeping and crash if
//  invoked off main).
//

@testable import KlaviyoSwift
import XCTest

@MainActor
final class DispatchOnMainThreadTests: XCTestCase {
    override func setUp() {
        super.setUp()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    func testRunsBlockOnMainActorWhenCalledFromMain() {
        let exp = XCTestExpectation(description: "block ran on main")
        dispatchOnMainThread {
            XCTAssertTrue(Thread.isMainThread, "block must run on main")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testRunsBlockOnMainActorWhenCalledFromBackgroundThread() {
        let exp = XCTestExpectation(description: "block ran on main")
        DispatchQueue.global(qos: .userInitiated).async {
            dispatchOnMainThread {
                XCTAssertTrue(Thread.isMainThread, "block must hop to main when called off-thread")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testPreservesOrderingAcrossMultipleDispatches() {
        // Regression test for the secondary fix: `handle()` schedules side effects via
        // `dispatchOnMainThread(action:)` (which submits a Task that hops to MainActor)
        // and then calls `dispatchOnMainThread(completionHandler)`. Hosts that observe SDK
        // state immediately after their completion handler fires (e.g., the KlaviyoSDKTests
        // action-button cases that check `capturedActions`) depend on the side-effect Tasks
        // draining BEFORE the completion Task. Both paths route through MainActor, and Tasks
        // submitted to the same actor execute in submission order, so the second block must
        // run after the first.
        let order = NSMutableArray()
        let firstRan = XCTestExpectation(description: "first block")
        let secondRan = XCTestExpectation(description: "second block")
        dispatchOnMainThread {
            order.add("first")
            firstRan.fulfill()
        }
        dispatchOnMainThread {
            order.add("second")
            secondRan.fulfill()
        }
        wait(for: [firstRan, secondRan], timeout: 2.0, enforceOrder: true)
        XCTAssertEqual(order as? [String], ["first", "second"])
    }

    func testPreservesOrderingBetweenActionAndClosureForms() {
        // The actual pattern in `KlaviyoSDK.handle(notificationResponse:...)` interleaves
        // the two overloads: side effects dispatch via `dispatchOnMainThread(action:)` and
        // the user-supplied completion handler dispatches via `dispatchOnMainThread(_:)`.
        // Both overloads are unified on `Task { @MainActor in ... }` so they share the
        // main-actor serial executor and observe submission-order FIFO. If somebody ever
        // splits the implementations again into mixed Task isolation forms (e.g., one
        // uses `Task { @MainActor in ... }` and the other uses `Task { await MainActor.run
        // { ... } }`), the two forms can interleave on the executor and this test will
        // fail — by design, to flag the regression before it ships.
        let order = NSMutableArray()
        let actionRan = XCTestExpectation(description: "action ran")
        let closureRan = XCTestExpectation(description: "closure ran")

        klaviyoSwiftEnvironment.send = { _ in
            order.add("action")
            actionRan.fulfill()
            return nil
        }

        dispatchOnMainThread(action: .resetProfile)
        dispatchOnMainThread {
            order.add("closure")
            closureRan.fulfill()
        }

        wait(for: [actionRan, closureRan], timeout: 2.0, enforceOrder: true)
        XCTAssertEqual(order as? [String], ["action", "closure"])
    }
}
