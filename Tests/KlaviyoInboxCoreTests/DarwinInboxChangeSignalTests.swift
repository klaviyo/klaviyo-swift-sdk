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
    /// How long to wait for a post that should arrive. Waiting returns the moment it does, so a long bound
    /// costs nothing when it passes. CI runners stall the whole test process for seconds at a time, and a
    /// short bound failed every test here at once on one of them.
    private static let deliveryTimeout: TimeInterval = 20

    private var appGroup: InboxAppGroup {
        let identifier = groupIdentifier
        return InboxAppGroup(identifier: { identifier }, containerURL: { _ in nil })
    }

    /// Waits for the first element of `stream`, or returns false after `seconds`.
    private func receivesChange(
        on stream: AsyncStream<Void>,
        within seconds: TimeInterval = deliveryTimeout,
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

    /// Counts the elements of a stream for the whole test. Unlike `receivesChange`, it never cancels a pending
    /// `next()`, which would end the stream.
    private final class Listener: @unchecked Sendable {
        private let lock = NSLock()
        private var total = 0
        private var task: Task<Void, Never>?

        init(_ stream: AsyncStream<Void>) {
            task = Task { [self] in
                for await _ in stream { increment() }
            }
        }

        var received: Int {
            lock.lock()
            defer { lock.unlock() }
            return total
        }

        private func increment() {
            lock.lock()
            defer { lock.unlock() }
            total += 1
        }

        /// Polls until the received count passes `value`, or returns false after `seconds`.
        func receivedMore(
            than value: Int,
            within seconds: TimeInterval = DarwinInboxChangeSignalTests.deliveryTimeout
        ) async -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if received > value { return true }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return received > value
        }

        func stop() { task?.cancel() }
    }

    @Test
    func aPostOnAnotherAppGroupIsNotHeard() async {
        let otherIdentifier = "group.other.\(UUID().uuidString)"
        let other = DarwinInboxChangeSignal(
            appGroup: InboxAppGroup(identifier: { otherIdentifier }, containerURL: { _ in nil })
        )
        let listener = Listener(DarwinInboxChangeSignal(appGroup: appGroup).changes())
        let otherListener = Listener(other.changes())
        defer { listener.stop(); otherListener.stop() }
        other.post()
        // The other group's own listener hearing it proves the post was delivered, so silence on `listener`
        // means the groups are isolated and not that the post was slow.
        let delivered = await otherListener.receivedMore(than: 0)
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(delivered)
        #expect(listener.received == 0)
    }

    @Test
    func aListenerStillHearsAfterABurstOfPosts() async {
        let signal = DarwinInboxChangeSignal(appGroup: appGroup)
        let listener = Listener(signal.changes())
        defer { listener.stop() }
        for _ in 0..<5 { signal.post() }
        let heardBurst = await listener.receivedMore(than: 0)
        // Posts may coalesce, so let any stragglers arrive, then check one more still gets through.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let settled = listener.received
        signal.post()
        let heardAfterwards = await listener.receivedMore(than: settled)
        #expect(heardBurst)
        #expect(heardAfterwards)
    }

    /// The observer is registered with an unretained pointer, so it has to be removed before it is freed.
    /// A missed removal would call into freed memory on the next post, so the test passes by not crashing.
    @Test
    func postingAfterAStreamEndsIsSafe() async {
        let signal = DarwinInboxChangeSignal(appGroup: appGroup)
        for _ in 0..<20 {
            _ = signal.changes()
            signal.post()
        }
        let consumer = Task { for await _ in signal.changes() {} }
        consumer.cancel()
        await consumer.value
        signal.post()
        // A fresh listener still works, so removing the old ones did not disturb the center.
        let heard = await receivesChange(on: signal.changes()) { signal.post() }
        #expect(heard)
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
