//
//  ReachabilityTests.swift
//  KlaviyoCoreTests
//

@testable import KlaviyoCore
import Network
import XCTest

final class ReachabilityTests: XCTestCase {
    private func status(
        _ pathStatus: NWPath.Status,
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) -> Reachability.NetworkStatus {
        Reachability.NetworkStatus(
            pathStatus: pathStatus,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }

    func testSatisfiedUnmeteredPathMapsToWiFi() {
        XCTAssertEqual(status(.satisfied), .reachableViaWiFi)
    }

    func testSatisfiedExpensivePathMapsToWWAN() {
        XCTAssertEqual(status(.satisfied, isExpensive: true), .reachableViaWWAN)
    }

    func testSatisfiedConstrainedPathMapsToWWAN() {
        XCTAssertEqual(status(.satisfied, isConstrained: true), .reachableViaWWAN)
    }

    func testSatisfiedExpensiveAndConstrainedPathMapsToWWAN() {
        XCTAssertEqual(status(.satisfied, isExpensive: true, isConstrained: true), .reachableViaWWAN)
    }

    func testRequiresConnectionPathCountsAsReachable() {
        XCTAssertEqual(status(.requiresConnection), .reachableViaWiFi)
        XCTAssertEqual(status(.requiresConnection, isExpensive: true), .reachableViaWWAN)
    }

    func testUnsatisfiedPathMapsToNotReachable() {
        XCTAssertEqual(status(.unsatisfied), .notReachable)
        XCTAssertEqual(status(.unsatisfied, isExpensive: true, isConstrained: true), .notReachable)
    }
}
