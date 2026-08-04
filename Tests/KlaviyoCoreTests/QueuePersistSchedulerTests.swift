//
//  QueuePersistSchedulerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/4/26.
//

@testable import KlaviyoCore
import XCTest

final class QueuePersistSchedulerTests: XCTestCase {
    func testScheduledWorkRuns() {
        let scheduler = DispatchQueuePersistScheduler()
        let work = expectation(description: "work ran")
        _ = scheduler.schedule(after: 0.01) { work.fulfill() }
        wait(for: [work], timeout: 1.0)
    }

    func testCancelPreventsWork() {
        let scheduler = DispatchQueuePersistScheduler()
        let work = expectation(description: "work ran")
        work.isInverted = true
        let token = scheduler.schedule(after: 0.05) { work.fulfill() }
        token.cancel()
        wait(for: [work], timeout: 0.3)
    }
}
