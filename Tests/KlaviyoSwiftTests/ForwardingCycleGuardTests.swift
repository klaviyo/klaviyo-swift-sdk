//
//  ForwardingCycleGuardTests.swift
//  KlaviyoSwiftTests
//
//  Created by Glenn Brannelly on 5/30/26.
//

@testable import KlaviyoSwift
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct ForwardingCycleGuardTests {
    /// `enter` must return depth 0 on the first call for a given ID.
    @Test
    func returnsZeroOnFirstCall() {
        let cycleGuard = ForwardingCycleGuard()
        let id = UUID().uuidString
        #expect(cycleGuard.enter(id) == 0)
    }

    /// Each re-entrant `enter` for the same in-flight ID returns the next depth.
    @Test
    func incrementsDepthOnReentry() {
        let cycleGuard = ForwardingCycleGuard()
        let id = UUID().uuidString
        #expect(cycleGuard.enter(id) == 0)
        #expect(cycleGuard.enter(id) == 1)
        #expect(cycleGuard.enter(id) == 2)
    }

    /// After a matching `leave`, a fresh `enter` for the same ID starts back at depth 0.
    @Test
    func resetsToZeroAfterFullyLeaving() {
        let cycleGuard = ForwardingCycleGuard()
        let id = UUID().uuidString
        _ = cycleGuard.enter(id)
        cycleGuard.leave(id)
        #expect(cycleGuard.enter(id) == 0)
    }

    /// `leave` unwinds one level at a time, mirroring nested `enter` calls.
    @Test
    func leaveUnwindsOneLevelAtATime() {
        let cycleGuard = ForwardingCycleGuard()
        let id = UUID().uuidString
        _ = cycleGuard.enter(id)
        _ = cycleGuard.enter(id)
        cycleGuard.leave(id)
        #expect(cycleGuard.enter(id) == 1)
    }

    /// Distinct IDs must not interfere with each other.
    @Test
    func distinctIdsAreIndependent() {
        let cycleGuard = ForwardingCycleGuard()
        let firstId = UUID().uuidString
        let secondId = UUID().uuidString
        _ = cycleGuard.enter(firstId)
        #expect(cycleGuard.enter(secondId) == 0)
    }
}
#endif
