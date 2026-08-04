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
    }

    override func tearDown() {
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
