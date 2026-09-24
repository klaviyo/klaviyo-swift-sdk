//
//  SpyRequestQueue.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/11/26.
//

@testable import KlaviyoCore
import Foundation

/// Test double for `RequestQueueProtocol` that records lifecycle/flush invocations so wiring tests
/// can assert orchestration drives the actor without exercising the real flush engine. Injected via
/// `klaviyoSwiftEnvironment.requestQueue = spy`. Because it does NOT touch `QueueStore`, tests that
/// also assert queue contents stay deterministic.
actor SpyRequestQueue: RequestQueueProtocol {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var flushNowCount = 0
    private(set) var connectivityStatuses: [Reachability.NetworkStatus] = []

    func start() async {
        startCount += 1
    }

    func stop() async {
        stopCount += 1
    }

    func flushNow() async {
        flushNowCount += 1
    }

    func networkConnectivityChanged(_ status: Reachability.NetworkStatus) async {
        connectivityStatuses.append(status)
    }

    // MARK: - Async getters (cross-actor reads)

    func getStartCount() -> Int { startCount }
    func getStopCount() -> Int { stopCount }
    func getFlushNowCount() -> Int { flushNowCount }
    func getConnectivityStatuses() -> [Reachability.NetworkStatus] { connectivityStatuses }
}
