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
        isCellular: Bool = false
    ) -> Reachability.NetworkStatus {
        Reachability.NetworkStatus(pathStatus: pathStatus, isCellular: isCellular)
    }

    func testSatisfiedNonCellularPathMapsToWiFi() {
        XCTAssertEqual(status(.satisfied), .reachableViaWiFi)
    }

    func testSatisfiedCellularPathMapsToWWAN() {
        XCTAssertEqual(status(.satisfied, isCellular: true), .reachableViaWWAN)
    }

    func testRequiresConnectionPathCountsAsReachable() {
        XCTAssertEqual(status(.requiresConnection), .reachableViaWiFi)
        XCTAssertEqual(status(.requiresConnection, isCellular: true), .reachableViaWWAN)
    }

    func testUnsatisfiedPathMapsToNotReachable() {
        XCTAssertEqual(status(.unsatisfied), .notReachable)
        XCTAssertEqual(status(.unsatisfied, isCellular: true), .notReachable)
    }
}
