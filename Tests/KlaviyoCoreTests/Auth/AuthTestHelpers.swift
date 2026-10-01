//
//  AuthTestHelpers.swift
//  KlaviyoCore
//
//  Shared fixtures for ``AuthTokenManager`` test suites: JWT minting,
//  deterministic clock injection, and async-coordination primitives.
//

@testable import KlaviyoCore
import Combine
import Foundation

// MARK: - JWT minting

/// Builds a JWT with default `iat` slightly in the past and `exp` an hour
/// ahead so it passes ``JWTParser`` validation in the present.
func makeJWT(
    issuedAt: TimeInterval? = nil,
    expiresAt: TimeInterval? = nil,
    extraClaims: [String: Any] = [:]
) throws -> String {
    let nowSeconds = Date().timeIntervalSince1970
    let issuedAtSeconds = issuedAt ?? (nowSeconds - 60)
    let expiresAtSeconds = expiresAt ?? (nowSeconds + 3600)

    var payload: [String: Any] = extraClaims
    payload["iat"] = issuedAtSeconds
    payload["exp"] = expiresAtSeconds

    let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
    let headerSeg = try base64URLEncode(JSONSerialization.data(withJSONObject: header))
    let payloadSeg = try base64URLEncode(JSONSerialization.data(withJSONObject: payload))
    return "\(headerSeg).\(payloadSeg).signature"
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// MARK: - Identity

/// Identity source for managers that should invoke their provider: its profile has an
/// identifier, and it never changes, so suites running in parallel can share it.
let identifiedIdentity: VersionedIdentityReading = IdentityStore(
    initialIdentity: ProfileData(email: "user@example.com")
)

/// Identity source whose reads and emissions a test drives directly. ``emit(_:)`` updates
/// the value and notifies subscribers; ``setStaleRead(_:)`` changes only what reads return.
final class ControllableIdentity: VersionedIdentityReading, @unchecked Sendable {
    private let lock = NSLock()
    private let subject: CurrentValueSubject<VersionedProfile, Never>
    private var stored: VersionedProfile

    init(_ initial: VersionedProfile) {
        stored = initial
        subject = CurrentValueSubject(initial)
    }

    var versioned: VersionedProfile {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    var current: ProfileData {
        versioned.profile
    }

    var publisher: AnyPublisher<ProfileData, Never> {
        subject.map(\.profile).eraseToAnyPublisher()
    }

    var versionedPublisher: AnyPublisher<VersionedProfile, Never> {
        subject.eraseToAnyPublisher()
    }

    func stream() -> AsyncStream<ProfileData> {
        AsyncStream { $0.finish() }
    }

    func emit(_ value: VersionedProfile) {
        lock.lock()
        stored = value
        lock.unlock()
        subject.send(value)
    }

    func setStaleRead(_ value: VersionedProfile) {
        lock.lock()
        defer { lock.unlock() }
        stored = value
    }
}

extension AuthTokenManager {
    /// The tokens of ``refreshes()`` without their generation. The subscription is
    /// established before this returns.
    func tokens() -> AsyncStream<String> {
        let refreshes = refreshes()
        return AsyncStream { continuation in
            let forwarding = Task {
                for await refresh in refreshes {
                    continuation.yield(refresh.token)
                }
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }
}

/// Records whether the task that called ``record(_:)`` was cancelled, and lets a test await it.
actor CancellationObservation {
    private var value: Bool?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func record(_ isCancelled: Bool) {
        value = isCancelled
        waiters.forEach { $0.resume(returning: isCancelled) }
        waiters.removeAll()
    }

    func wait() async -> Bool {
        if let value { return value }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

// MARK: - Concurrency primitives

/// One-shot async gate. ``wait()`` suspends until ``open()`` is called; once
/// open it stays open. Used to interleave a provider's resumption with other
/// operations in deterministic order.
actor Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else { return }
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Counts provider invocations and lets tests await a specific call count
/// without sleeping. Every increment resumes any waiters whose threshold the
/// new value has reached, so tests block only as long as necessary.
actor CallCounter {
    private(set) var value = 0
    private var waiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    @discardableResult
    func increment() -> Int {
        value += 1
        waiters = waiters.compactMap { waiter in
            if value >= waiter.threshold {
                waiter.continuation.resume()
                return nil
            }
            return waiter
        }
        return value
    }

    func waitFor(atLeast threshold: Int) async throws {
        if value >= threshold { return }
        await withCheckedContinuation { continuation in
            waiters.append((threshold, continuation))
        }
    }
}

/// Mutable token holder used to change a registered provider's return value
/// over time without re-registering (re-registration would clear the cache
/// and defeat tests that depend on a warm cache).
actor TokenBox {
    private(set) var value: String

    init(_ initial: String) {
        value = initial
    }

    func set(_ token: String) {
        value = token
    }
}

/// Accumulates values delivered to a stream subscriber so tests can assert on
/// what was — or, just as importantly, was not — received. ``waitFor(atLeast:)``
/// lets a test *suspend* until an expected emission lands rather than spinning on
/// `Task.yield()`: spinning keeps the waiting task runnable and can starve the
/// consumer draining the stream, dropping the very emission under test.
actor TokenCollector {
    private(set) var received: [String] = []
    private var waiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func append(_ token: String) {
        received.append(token)
        waiters = waiters.compactMap { waiter in
            if received.count >= waiter.threshold {
                waiter.continuation.resume()
                return nil
            }
            return waiter
        }
    }

    /// Suspends until at least `threshold` values have been collected.
    func waitFor(atLeast threshold: Int) async {
        if received.count >= threshold { return }
        await withCheckedContinuation { continuation in
            waiters.append((threshold, continuation))
        }
    }
}

enum ProviderTestError: Error, Equatable {
    case network
}

// MARK: - Deterministic clock & sleep

/// Manually-advanced clock with a synchronously-readable `now`, injected as the
/// manager's `currentDate`. Tests move time explicitly via ``set(_:)`` /
/// ``advance(by:)`` instead of waiting on the real wall clock, so every
/// clock-sensitive decision the manager makes is deterministic. `NSLock`-guarded
/// because the manager reads `now()` from its actor while tests mutate it.
///
/// Injecting a clock here is also what keeps the auth suites off the SDK-wide
/// global `environment.date`, which sibling suites mutate concurrently under
/// Swift Testing's parallel execution (freezing it to 2009) — a shared global
/// clock would make acquisition-time validation flaky. This is the canonical
/// reason every auth suite injects its own time source rather than reaching
/// for the global environment.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func set(_ date: Date) {
        lock.lock()
        defer { lock.unlock() }
        current = date
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

/// Manually-set network reachability, injected as the manager's live
/// `reachabilityStatus` source. Lets a test model the real offline→online flow
/// the connectivity retry depends on — start `.notReachable` so arming doesn't
/// immediately kick, then ``set(_:)`` `.reachableViaWiFi` just before sending the
/// `.reachabilityChanged` transition so the handler's live re-read sees a path.
/// `NSLock`-guarded because the manager reads it from its actor while the test
/// mutates it. `nil` models an "unknown" reading.
final class TestReachability: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Reachability.NetworkStatus?

    init(_ start: Reachability.NetworkStatus? = nil) {
        value = start
    }

    func status() -> Reachability.NetworkStatus? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ status: Reachability.NetworkStatus?) {
        lock.lock()
        defer { lock.unlock() }
        value = status
    }
}

/// Gated stand-in for the manager's `sleeper`. Every `sleep(_:)` records its
/// entry and parks until the test ``release()``s it — so a scheduled refresh
/// fires exactly when the test advances the clock past its target and releases
/// the parked sleep, with no real waiting. ``waitUntilSleeping(atLeast:)`` lets
/// the test await the manager actually parking (which, because the refresh is
/// scheduled immediately after the cache is written, also confirms the prior
/// fetch has cached its token). Sleeps left parked at test end are harmless —
/// they simply never resume.
actor SleepGate {
    private var enteredCount = 0
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var pendingReleases = 0
    private var entryWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// Injected as the manager's `sleep` closure. Duration is ignored — virtual
    /// time is driven by the paired ``TestClock``.
    func sleep(_: UInt64) async {
        enteredCount += 1
        entryWaiters = entryWaiters.compactMap { waiter in
            if enteredCount >= waiter.threshold {
                waiter.continuation.resume()
                return nil
            }
            return waiter
        }
        if pendingReleases > 0 {
            pendingReleases -= 1
            return
        }
        await withCheckedContinuation { parked.append($0) }
    }

    /// Suspends until at least `threshold` sleeps have been entered.
    func waitUntilSleeping(atLeast threshold: Int = 1) async {
        if enteredCount >= threshold { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append((threshold, continuation))
        }
    }

    /// Wakes the oldest parked sleeper, or pre-authorizes the next `sleep(_:)`
    /// if none is parked yet.
    func release() {
        if parked.isEmpty {
            pendingReleases += 1
        } else {
            parked.removeFirst().resume()
        }
    }
}

// MARK: - Manager & stream fixtures

/// Returns the first element a stream delivers (or `nil` if it finishes
/// without delivering). Each call drives its own iterator, so independent
/// subscribers can be awaited concurrently.
func firstElement(of stream: AsyncStream<String>) async -> String? {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
}

/// Lifecycle source that emits nothing, for tests that don't exercise the
/// foreground transition path. Uses an `Empty` publisher so the observer
/// task simply parks on the await without ever firing.
func noopLifecycle() -> AppLifeCycleEvents {
    AppLifeCycleEvents(lifeCycleEvents: { Empty().eraseToAnyPublisher() })
}

/// Builds a manager driven by a deterministic clock and sleep gate.
///
/// Injects `clock` as the manager's `currentDate` and `gate` as its `sleep`,
/// so token validity, refresh scheduling, and refresh firing advance in
/// virtual time under the test's control instead of reading
/// `environment.date` and `Task.sleep`.
func makeManager(
    lifeCycle: AppLifeCycleEvents,
    clock: TestClock,
    gate: SleepGate,
    reachabilityStatus: @escaping () -> Reachability.NetworkStatus? = { nil }
) -> AuthTokenManager {
    AuthTokenManager(
        lifeCycle: lifeCycle,
        currentDate: { clock.now() },
        sleep: { await gate.sleep($0) },
        reachabilityStatus: reachabilityStatus,
        identity: identifiedIdentity
    )
}
