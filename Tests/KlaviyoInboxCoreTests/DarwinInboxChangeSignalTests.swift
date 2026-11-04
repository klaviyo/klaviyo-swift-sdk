//
//  DarwinInboxChangeSignalTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct DarwinInboxChangeSignalTests {
    /// Darwin notifications are process-wide and tests run in parallel, so each test gets its own group
    /// identifier instead of the fixtures' shared one. A struct suite is rebuilt per test.
    private let groupIdentifier = "group.test.\(UUID().uuidString)"
    private var appGroup: InboxAppGroup {
        let identifier = groupIdentifier
        return InboxAppGroup(identifier: { identifier }, containerURL: { _ in nil })
    }

    /// Waits for the first element of `stream`, or returns false after `seconds`.
    private func receivesChange(
        on stream: AsyncStream<Void>,
        within seconds: TimeInterval = 2,
        after trigger: () -> Void
    ) async -> Bool {
        var iterator = stream.makeAsyncIterator()
        trigger()
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await iterator.next() != nil }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test
    func aPostReachesAListenerOnTheSameAppGroup() async {
        let signal = DarwinInboxChangeSignal(appGroup: appGroup)
        let stream = signal.changes()
        let received = await receivesChange(on: stream) { signal.post() }
        #expect(received)
    }

    @Test
    func aPostOnAnotherAppGroupIsNotHeard() async {
        let listener = DarwinInboxChangeSignal(appGroup: appGroup)
        let otherGroup = InboxAppGroup(identifier: { "group.other" }, containerURL: { _ in nil })
        let stream = listener.changes()
        let received = await receivesChange(on: stream, within: 0.3) {
            DarwinInboxChangeSignal(appGroup: otherGroup).post()
        }
        #expect(!received)
    }

    @Test
    func aPostWithNoAppGroupIdentifierIsANoOp() async {
        let none = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })
        let signal = DarwinInboxChangeSignal(appGroup: none)
        signal.post()
        var iterator = signal.changes().makeAsyncIterator()
        let element: Void? = await iterator.next()
        #expect(element == nil)
    }
}

#endif
