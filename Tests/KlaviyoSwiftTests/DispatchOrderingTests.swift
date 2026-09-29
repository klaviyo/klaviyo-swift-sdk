//
//  DispatchOrderingTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoSwift
import Foundation
import KlaviyoCore
import XCTest

/// Regression coverage for out-of-order action dispatch through `dispatchOnMainThread`.
@MainActor
final class DispatchOrderingTests: XCTestCase {
    private var savedCoreEnvironment: KlaviyoEnvironment!
    private var savedEnvironment: KlaviyoSwiftEnvironment!

    override func setUp() {
        super.setUp()
        savedCoreEnvironment = environment
        savedEnvironment = klaviyoSwiftEnvironment
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        SharedStoreMirror.reset()
    }

    override func tearDown() {
        SharedStoreMirror.reset()
        environment = savedCoreEnvironment
        klaviyoSwiftEnvironment = savedEnvironment
        super.tearDown()
    }

    /// Consecutive dispatches must reduce in call order. Iterated because the pre-fix
    /// implementation inverted probabilistically (~8% per pair on device).
    func testConsecutiveDispatchesPreserveCallOrder() async {
        let iterations = 250

        for iteration in 0..<iterations {
            let bothReduced = expectation(description: "both actions reduced (iteration \(iteration))")
            let lock = NSLock()
            var observed: [String] = []

            klaviyoSwiftEnvironment.send = { action in
                lock.lock()
                observed.append(action.orderingLabel)
                let isComplete = observed.count == 2
                lock.unlock()
                if isComplete { bothReduced.fulfill() }
                return nil
            }

            dispatchOnMainThread(action: .setEmail("first@example.com"))
            dispatchOnMainThread(action: .setPhoneNumber("+15005550006"))

            await fulfillment(of: [bothReduced], timeout: 2.0)

            lock.lock()
            let result = observed
            lock.unlock()

            XCTAssertEqual(
                result,
                ["setEmail", "setPhoneNumber"],
                "actions must reduce in call order (iteration \(iteration))"
            )
        }
    }

    /// `initialize` and `dispatchOnMainThread` share `DispatchQueue.main`, so FIFO ordering
    /// keeps `.initialize` ahead of a following `set(email:)`, which requires initialization.
    func testDispatchAfterInitializeIsNotReorderedBeforeInitialize() async {
        let bothReduced = expectation(description: "initialize and setEmail both reduced")
        let lock = NSLock()
        var observed: [String] = []

        klaviyoSwiftEnvironment.send = { action in
            lock.lock()
            switch action {
            case .initialize: observed.append("initialize")
            case .setEmail: observed.append("setEmail")
            default: break
            }
            let done = observed.count == 2
            lock.unlock()
            if done { bothReduced.fulfill() }
            return nil
        }

        _ = KlaviyoSDK().initialize(with: "test-key")
        _ = KlaviyoSDK().set(email: "a@b.com")

        await fulfillment(of: [bothReduced], timeout: 2.0)

        lock.lock()
        let result = observed
        lock.unlock()
        XCTAssertEqual(result, ["initialize", "setEmail"], "setEmail must not reduce before initialize")
    }

    func testSetEmailAfterResetDoesNotReachReducerFirst() async {
        let bothReduced = expectation(description: "reset and email reduced")
        var observed: [String] = []
        klaviyoSwiftEnvironment.send = { action in
            switch action {
            case .resetProfile: observed.append("resetProfile")
            case .setEmail: observed.append("setEmail")
            default: break
            }
            if observed.count == 2 { bothReduced.fulfill() }
            return nil
        }

        KlaviyoSDK().resetProfile()
        KlaviyoSDK().set(email: "next@example.com")
        await fulfillment(of: [bothReduced], timeout: 2)

        XCTAssertEqual(observed, ["resetProfile", "setEmail"])
    }

    func testFacadeActionsPreserveOrderAcrossResets() async {
        let allReduced = expectation(description: "facade actions reduced")
        var observed: [String] = []
        klaviyoSwiftEnvironment.send = { action in
            switch action {
            case .resetProfile: observed.append("resetProfile")
            case .setEmail: observed.append("setEmail")
            case .enqueueEvent: observed.append("enqueueEvent")
            case .setPhoneNumber: observed.append("setPhoneNumber")
            case .initialize: observed.append("initialize")
            default: break
            }
            if observed.count == 6 { allReduced.fulfill() }
            return nil
        }

        let sdk = KlaviyoSDK()
        sdk.resetProfile()
        sdk.set(email: "next@example.com")
        sdk.create(event: Event(name: .customEvent("after-reset")))
        sdk.resetProfile()
        sdk.set(phoneNumber: "+15005550006")
        sdk.initialize(with: "next-key")
        await fulfillment(of: [allReduced], timeout: 2)

        XCTAssertEqual(
            observed,
            ["resetProfile", "setEmail", "enqueueEvent", "resetProfile", "setPhoneNumber", "initialize"]
        )
    }
}

extension KlaviyoAction {
    fileprivate var orderingLabel: String {
        switch self {
        case .setEmail: return "setEmail"
        case .setPhoneNumber: return "setPhoneNumber"
        default: return "other"
        }
    }
}
