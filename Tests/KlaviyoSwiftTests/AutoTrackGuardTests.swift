//
//  AutoTrackGuardTests.swift
//  KlaviyoSwiftTests
//
//  Created by Glenn Brannelly on 6/1/26.
//

@testable import KlaviyoSwift

#if canImport(Testing)
import Testing

@Suite
struct AutoTrackGuardTests {
    @Test
    func markThenWasTrackedReturnsTrue() {
        let tracker = AutoTrackGuard()
        tracker.markTracked("abc")
        #expect(tracker.wasTracked("abc"))
    }

    @Test
    func wasTrackedForUnknownIdReturnsFalse() {
        let tracker = AutoTrackGuard()
        #expect(!tracker.wasTracked("unknown"))
    }

    @Test
    func idempotentInsertDoesNotDuplicateOrder() {
        let tracker = AutoTrackGuard()
        tracker.markTracked("first")
        tracker.markTracked("first") // duplicate — must not double-count in order
        for i in 0..<(AutoTrackGuard.capacity - 1) {
            tracker.markTracked("id-\(i)")
        }
        // 256 unique IDs total: "first" + 255 others — "first" should still be present
        #expect(tracker.wasTracked("first"), "double insert must not advance eviction position")
        // one more tips over capacity, evicting "first"
        tracker.markTracked("tip-over")
        #expect(!tracker.wasTracked("first"), "first should be evicted as oldest")
    }

    @Test
    func fifoEvictionEvictsOldestAtCapacity() {
        let tracker = AutoTrackGuard()
        let first = "id-0"
        for i in 0..<AutoTrackGuard.capacity {
            tracker.markTracked("id-\(i)")
        }
        #expect(tracker.wasTracked(first))
        tracker.markTracked("id-overflow")
        #expect(!tracker.wasTracked(first), "oldest entry should be evicted")
        #expect(tracker.wasTracked("id-overflow"))
        #expect(tracker.wasTracked("id-\(AutoTrackGuard.capacity - 1)"))
    }

    @Test
    func clearResetsAllState() {
        let tracker = AutoTrackGuard()
        tracker.markTracked("abc")
        tracker.clear()
        #expect(!tracker.wasTracked("abc"))
    }

    @Test
    func concurrentAccessDoesNotCrash() async {
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
#endif
