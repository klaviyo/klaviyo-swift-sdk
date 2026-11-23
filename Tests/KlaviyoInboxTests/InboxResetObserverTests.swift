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
    /// Guards every field. The observer's task and the test body both touch them.
    private let lock = NSLock()
    private var entries: [String] = []
    private var storedMarker: UUID?
    private var remainingFailures = 0

    var log: [String] { lock.withLock { entries } }
    var marker: UUID? {
        get { lock.withLock { storedMarker } }
        set { lock.withLock { storedMarker = newValue } }
    }

    var failClears: Int {
        get { lock.withLock { remainingFailures } }
        set { lock.withLock { remainingFailures = newValue } }
    }

    func add(_ entry: String) { lock.withLock { entries.append(entry) } }

    /// Simulates a reset that arrives while a clear is running: the next acknowledgement finds a newer
    /// marker in place of the one it was given, so it removes nothing, and the newer one stays pending.
    func setNewerMarkerAfterAcknowledge() {
        lock.withLock { storedMarker = UUID() }
    }

    /// Removes the marker if it is still `id`, then logs the acknowledgement, as one step. A test that
    /// sees "ack" in the log therefore knows the removal is already done, and a marker it installs after
    /// that is never removed by this call.
    func acknowledge(_ id: UUID) {
        lock.withLock {
            if storedMarker == id { storedMarker = nil }
            entries.append("ack")
        }
    }

    /// Consumes one injected failure, if any are left.
    func takeFailure() -> Bool {
        lock.withLock {
            guard remainingFailures > 0 else { return false }
            remainingFailures -= 1
            return true
        }
    }
}

/// Lets a test hold a clear open until it chooses to let it finish.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
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
                clearer: ResetClearer(
                    pendingMarker: { calls.marker },
                    acknowledge: { calls.acknowledge($0) },
                    clearAll: {
                        calls.add("clear")
                        if calls.takeFailure() { throw InboxError.storageFailure }
                        try await clear()
                    }
                )
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

    private func clearer(
        _ calls: Calls,
        acknowledge: (@Sendable (UUID) -> Void)? = nil,
        clear: @escaping @Sendable () async throws -> Void = {}
    ) -> ResetClearer {
        ResetClearer(
            pendingMarker: { calls.marker },
            acknowledge: acknowledge ?? { calls.acknowledge($0) },
            clearAll: {
                calls.add("clear")
                if calls.takeFailure() { throw InboxError.storageFailure }
                try await clear()
            }
        )
    }

    @Test
    func clearingAPendingResetDoesNothingWhenNoneIsPending() async throws {
        let calls = Calls()
        try await clearer(calls).clearPending()
        #expect(calls.log.isEmpty)
    }

    @Test
    func clearingAPendingResetRemovesTheMarkerAfterTheClear() async throws {
        let calls = Calls()
        calls.marker = UUID()
        try await clearer(calls).clearPending()
        #expect(calls.log == ["clear", "ack"])
        #expect(calls.marker == nil)
    }

    @Test
    func aResetThatArrivesDuringAClearIsClearedBeforeReturning() async throws {
        let calls = Calls()
        calls.marker = UUID()
        // A newer reset lands while the first clear runs, so the acknowledgement finds a different marker.
        let clearer = clearer(calls, clear: {
            if calls.log.filter({ $0 == "clear" }).count == 1 { calls.setNewerMarkerAfterAcknowledge() }
        })
        try await clearer.clearPending()
        #expect(calls.log == ["clear", "ack", "clear", "ack"])
        #expect(calls.marker == nil)
    }

    @Test
    func aMarkerThatCannotBeRemovedIsClearedOnceNotRepeatedly() async throws {
        let calls = Calls()
        calls.marker = UUID()
        try await clearer(calls, acknowledge: { _ in calls.add("ack") }).clearPending()
        #expect(calls.log == ["clear", "ack"])
        #expect(calls.marker != nil)
    }

    @Test
    func aFailedClearThrowsAndKeepsTheMarker() async {
        let calls = Calls()
        calls.marker = UUID()
        calls.failClears = 1
        await #expect(throws: InboxError.storageFailure) { try await clearer(calls).clearPending() }
        #expect(calls.log == ["clear"])
        #expect(calls.marker != nil)
    }

    @Test
    func callersThatFindTheSameResetShareOneClear() async throws {
        let calls = Calls()
        calls.marker = UUID()
        let started = Gate()
        let release = Gate()
        let clearer = clearer(calls, clear: {
            await started.open()
            await release.wait()
        })
        let first = Task { try await clearer.clearPending() }
        await started.wait()
        // The first clear is running and its marker is not acknowledged yet, as when the observer and a read meet.
        let second = Task { try await clearer.clearPending() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await release.open()
        try await first.value
        try await second.value
        #expect(calls.log == ["clear", "ack"], "a second delete could remove a message captured after the first")
    }

    @Test
    func aFailedSharedClearReachesEveryWaiterAndTheNextCallRetries() async throws {
        let calls = Calls()
        calls.marker = UUID()
        calls.failClears = 1
        let started = Gate()
        let release = Gate()
        let clearer = clearer(calls, clear: {})
        let slowFailing = ResetClearer(
            pendingMarker: { calls.marker },
            acknowledge: { calls.acknowledge($0) },
            clearAll: {
                calls.add("clear")
                await started.open()
                await release.wait()
                if calls.takeFailure() { throw InboxError.storageFailure }
            }
        )
        let first = Task { try await slowFailing.clearPending() }
        await started.wait()
        let second = Task { try await slowFailing.clearPending() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await release.open()
        await #expect(throws: InboxError.storageFailure) { try await first.value }
        await #expect(throws: InboxError.storageFailure) { try await second.value }
        #expect(calls.log == ["clear"])
        #expect(calls.marker != nil)
        // The failure is not remembered: the next call starts a fresh clear and succeeds.
        try await clearer.clearPending()
        #expect(calls.marker == nil)
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
                clearer: ResetClearer(
                    pendingMarker: { calls.marker },
                    acknowledge: { _ in calls.marker = nil },
                    clearAll: { try await store.clearAll() }
                )
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
