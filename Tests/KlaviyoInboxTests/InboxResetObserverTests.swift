//
//  InboxResetObserverTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoCore
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

/// Records what the observer asked the store and the marker to do, in order.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var marker: UUID?
    var failClears = 0

    var log: [String] { lock.withLock { entries } }
    func add(_ entry: String) { lock.withLock { entries.append(entry) } }
}

@Suite
struct InboxResetObserverTests {
    private func run(
        _ calls: Calls,
        resets: AsyncStream<Void>,
        clear: @escaping @Sendable () async throws -> Void = {}
    ) -> Task<Void, Never> {
        Task {
            await InboxResetObserver.run(
                resets: resets,
                pendingMarker: { calls.marker },
                acknowledge: { id in
                    calls.add("ack")
                    if calls.marker == id { calls.marker = nil }
                },
                clearAll: {
                    calls.add("clear")
                    if calls.failClears > 0 {
                        calls.failClears -= 1
                        throw InboxError.storageFailure
                    }
                    try await clear()
                }
            )
        }
    }

    private func waitFor(_ condition: @escaping @Sendable () -> Bool) async {
        for _ in 0..<150 where !condition() {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @Test
    func aResetFromBeforeTheObserverStartedIsClearedAtStart() async {
        let calls = Calls()
        calls.marker = UUID()
        let (resets, continuation) = AsyncStream.makeStream(of: Void.self)
        let task = run(calls, resets: resets)
        await waitFor { calls.log == ["clear", "ack"] }
        continuation.finish()
        await task.value
        #expect(calls.log == ["clear", "ack"])
        #expect(calls.marker == nil)
    }

    @Test
    func nothingIsClearedWhenNoResetHappened() async {
        let calls = Calls()
        let (resets, continuation) = AsyncStream.makeStream(of: Void.self)
        let task = run(calls, resets: resets)
        continuation.finish()
        await task.value
        #expect(calls.log.isEmpty)
    }

    @Test
    func aLiveResetClearsTheInbox() async {
        let calls = Calls()
        let (resets, continuation) = AsyncStream.makeStream(of: Void.self)
        let task = run(calls, resets: resets)
        calls.marker = UUID()
        continuation.yield()
        await waitFor { calls.log == ["clear", "ack"] }
        continuation.finish()
        await task.value
        #expect(calls.log == ["clear", "ack"])
    }

    @Test
    func aFailedClearKeepsTheMarkerSoItIsTriedAgain() async {
        let calls = Calls()
        calls.marker = UUID()
        calls.failClears = 1
        let (resets, continuation) = AsyncStream.makeStream(of: Void.self)
        let task = run(calls, resets: resets)
        await waitFor { calls.log == ["clear"] }
        #expect(calls.marker != nil)
        continuation.yield()
        await waitFor { calls.log == ["clear", "clear", "ack"] }
        continuation.finish()
        await task.value
        #expect(calls.log == ["clear", "clear", "ack"])
        #expect(calls.marker == nil)
    }

    @Test
    func clearsRunOneAtATimeInTheOrderTheResetsArrived() async {
        let calls = Calls()
        let (resets, continuation) = AsyncStream.makeStream(of: Void.self)
        let task = run(calls, resets: resets, clear: { try? await Task.sleep(nanoseconds: 50_000_000) })
        calls.marker = UUID()
        continuation.yield()
        await waitFor { calls.log == ["clear", "ack"] }
        calls.marker = UUID()
        continuation.yield()
        await waitFor { calls.log == ["clear", "ack", "clear", "ack"] }
        continuation.finish()
        await task.value
        #expect(calls.log == ["clear", "ack", "clear", "ack"])
    }

    @Test
    func aResetClearsEveryCompanysMessagesAndRemovesTheMarker() async throws {
        let store = InboxStoreFixtures.store(appGroup: InboxStoreFixtures.temporaryAppGroup())
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 2, companyID: "XyZ789")
        let calls = Calls()
        calls.marker = UUID()
        let (resets, continuation) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            await InboxResetObserver.run(
                resets: resets,
                pendingMarker: { calls.marker },
                acknowledge: { _ in calls.marker = nil },
                clearAll: { try await store.clearAll() }
            )
        }
        await waitFor { calls.marker == nil }
        continuation.finish()
        await task.value
        let first = try await store.message(id: "tm-1")
        let other = try await store.message(id: "other-1")
        #expect(first == nil)
        #expect(other == nil)
    }
}

#endif
