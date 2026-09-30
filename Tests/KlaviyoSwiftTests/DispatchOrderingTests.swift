//
//  DispatchOrderingTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoSwift
import Foundation
import KlaviyoCore
import XCTest

/// Regression coverage for out-of-order work dispatch through `dispatchOnMainThread`.
@MainActor
final class DispatchOrderingTests: XCTestCase {
    private var savedCoreEnvironment: KlaviyoEnvironment!
    private var savedEnvironment: KlaviyoSwiftEnvironment!

    override func setUp() {
        super.setUp()
        savedCoreEnvironment = environment
        savedEnvironment = klaviyoSwiftEnvironment
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        LifecycleState.shared.reset()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    override func tearDown() {
        environment = savedCoreEnvironment
        klaviyoSwiftEnvironment = savedEnvironment
        LifecycleState.shared.reset()
        super.tearDown()
    }

    /// Consecutive dispatches must run in call order. Iterated because the pre-fix implementation
    /// inverted probabilistically (~8% per pair on device).
    func testConsecutiveDispatchesPreserveCallOrder() async {
        let iterations = 250

        for iteration in 0..<iterations {
            let bothRan = expectation(description: "both closures ran (iteration \(iteration))")
            let lock = NSLock()
            var observed: [String] = []

            func record(_ label: String) {
                lock.lock()
                observed.append(label)
                let isComplete = observed.count == 2
                lock.unlock()
                if isComplete { bothRan.fulfill() }
            }

            dispatchOnMainThread { record("setEmail") }
            dispatchOnMainThread { record("setPhoneNumber") }

            await fulfillment(of: [bothRan], timeout: 2.0)

            lock.lock()
            let result = observed
            lock.unlock()

            XCTAssertEqual(
                result,
                ["setEmail", "setPhoneNumber"],
                "closures must run in call order (iteration \(iteration))"
            )
        }
    }

    /// `initialize` and `dispatchOnMainThread` share `DispatchQueue.main`, so FIFO ordering keeps the
    /// `initialize` work ahead of a following `set(email:)`, which depends on initialization. After
    /// both public calls settle, the SDK is initialized and the email has been applied to the
    /// canonical identity store.
    func testDispatchAfterInitializeIsNotReorderedBeforeInitialize() async {
        _ = KlaviyoSDK().initialize(with: "test-key")
        _ = KlaviyoSDK().set(email: "a@b.com")

        // Both closures hop through the shared main queue; wait for them to drain and for the async
        // initialize tail to settle the lifecycle + identity.
        let settled = expectation(description: "email applied after initialize")
        func poll() {
            if IdentityStore.shared.current.email == "a@b.com" {
                settled.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { poll() }
            }
        }
        poll()
        await fulfillment(of: [settled], timeout: 2.0)

        XCTAssertEqual(IdentityStore.shared.current.email, "a@b.com")
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, "test-key")
    }
}
