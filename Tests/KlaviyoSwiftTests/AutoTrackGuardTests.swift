//
//  AutoTrackGuardTests.swift
//  KlaviyoSwiftTests
//
//  Created by Glenn Brannelly on 6/1/26.
//

@testable import KlaviyoSwift
import XCTest

class AutoTrackGuardTests: XCTestCase {
    func testMarkThenWasTrackedReturnsTrue() {
        let tracker = AutoTrackGuard()
        tracker.markTracked("abc")
        XCTAssertTrue(tracker.wasTracked("abc"))
    }

    func testWasTrackedForUnknownIdReturnsFalse() {
        let tracker = AutoTrackGuard()
        XCTAssertFalse(tracker.wasTracked("unknown"))
    }

    func testIdempotentInsertDoesNotDuplicateOrder() {
        let tracker = AutoTrackGuard()
        tracker.markTracked("first")
        tracker.markTracked("first") // duplicate — must not double-count in order
        for i in 0..<(AutoTrackGuard.capacity - 1) {
            tracker.markTracked("id-\(i)")
        }
        // 256 unique IDs total: "first" + 255 others — "first" should still be present
        XCTAssertTrue(tracker.wasTracked("first"), "double insert must not advance eviction position")
        // one more tips over capacity, evicting "first"
        tracker.markTracked("tip-over")
        XCTAssertFalse(tracker.wasTracked("first"), "first should be evicted as oldest")
    }

    func testFifoEvictionEvictsOldestAtCapacity() {
        let tracker = AutoTrackGuard()
        let first = "id-0"
        for i in 0..<AutoTrackGuard.capacity {
            tracker.markTracked("id-\(i)")
        }
        XCTAssertTrue(tracker.wasTracked(first))
        tracker.markTracked("id-overflow")
        XCTAssertFalse(tracker.wasTracked(first), "oldest entry should be evicted")
        XCTAssertTrue(tracker.wasTracked("id-overflow"))
        XCTAssertTrue(tracker.wasTracked("id-\(AutoTrackGuard.capacity - 1)"))
    }

    func testClearResetsAllState() {
        let tracker = AutoTrackGuard()
        tracker.markTracked("abc")
        tracker.clear()
        XCTAssertFalse(tracker.wasTracked("abc"))
    }

    func testConcurrentAccessDoesNotCrash() async {
        let tracker = AutoTrackGuard()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<8 {
                group.addTask { tracker.markTracked("write-\(i)") }
            }
            for i in 0..<4 {
                group.addTask { _ = tracker.wasTracked("read-\(i)") }
            }
        }
    }
}
