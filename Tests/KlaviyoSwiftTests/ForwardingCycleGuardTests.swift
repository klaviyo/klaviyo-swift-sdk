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
    /// `begin` must return `true` on the first call for a given ID.
    @Test
    func returnsTrueOnFirstCall() {
        let cycleGuard = ForwardingCycleGuard()
        let id = UUID().uuidString
        #expect(cycleGuard.begin(id) == true)
    }

    /// `begin` must return `false` when already in progress for the same ID.
    @Test
    func returnsFalseWhenAlreadyForwarding() {
        let cycleGuard = ForwardingCycleGuard()
        let id = UUID().uuidString
        _ = cycleGuard.begin(id)
        #expect(cycleGuard.begin(id) == false)
    }

    /// After `end`, the same ID must be accepted again.
    @Test
    func allowsSubsequentBeginAfterEnd() {
        let cycleGuard = ForwardingCycleGuard()
        let id = UUID().uuidString
        _ = cycleGuard.begin(id)
        cycleGuard.end(id)
        #expect(cycleGuard.begin(id) == true)
    }

    /// Distinct IDs must not interfere with each other.
    @Test
    func distinctIdsAreIndependent() {
        let cycleGuard = ForwardingCycleGuard()
        let firstId = UUID().uuidString
        let secondId = UUID().uuidString
        _ = cycleGuard.begin(firstId)
        #expect(cycleGuard.begin(secondId) == true)
    }
}
#endif
