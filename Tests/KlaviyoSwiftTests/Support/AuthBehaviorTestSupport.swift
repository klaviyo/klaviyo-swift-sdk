//
//  AuthBehaviorTestSupport.swift
//  klaviyo-swift-sdk
//
//  Shared doubles for the KlaviyoSwift auth-behavior suites. Mirrors the doubles in
//  Tests/KlaviyoCoreTests/Auth/AuthTestHelpers.swift, which live in a different test target
//  and are not visible here (SPM test targets cannot depend on one another).
//

@testable import KlaviyoCore
import Combine
import Foundation

// MARK: - JWT minting

/// Builds a JWT with `iat` just before and `exp` an hour after `validAt`, so it passes
/// ``JWTParser`` validation at that time. Each distinct `subject` yields a distinct token.
func makeBehaviorTestJWT(subject: String, validAt date: Date) throws -> String {
    let nowSeconds = date.timeIntervalSince1970
    let payload: [String: Any] = ["sub": subject, "iat": nowSeconds - 60, "exp": nowSeconds + 3600]
    return try [JSONSerialization.data(withJSONObject: ["alg": "HS256", "typ": "JWT"]),
                JSONSerialization.data(withJSONObject: payload),
                Data(subject.utf8)]
        .map {
            $0.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        .joined(separator: ".")
}

// MARK: - Async coordination

/// One-shot async gate: ``wait()`` suspends until ``open()``; once open it stays open.
actor BehaviorLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else { return }
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Stand-in for the manager's fetch-timeout sleep that never wakes, so a test's calls are
/// not bound by a real-time budget.
let behaviorNeverTimesOut: @Sendable (UInt64) async -> Void = { _ in await BehaviorLatch().wait() }

// MARK: - Provider double

/// Provider double recording every invocation. Each call mints a distinct valid JWT and can
/// be held open via a latch captured at call time, letting a test interleave a provider's
/// resumption with identity changes in a deterministic order.
final class RecordingAuthProvider: @unchecked Sendable {
    struct Invocation: Equatable {
        let number: Int
    }

    private let lock = NSLock()
    private(set) var invocations: [Invocation] = []
    private var latches: [BehaviorLatch] = []
    private let currentDate: () -> Date

    init(currentDate: @escaping () -> Date = { Date() }) {
        self.currentDate = currentDate
    }

    var invocationCount: Int {
        lock.withLock { invocations.count }
    }

    /// Makes the next provider invocation park until the returned latch opens (or its task
    /// is cancelled). Must be called before the fetch that should be held starts.
    @discardableResult
    func holdNextInvocation() -> BehaviorLatch {
        let latch = BehaviorLatch()
        lock.withLock { latches.append(latch) }
        return latch
    }

    /// The closure handed to the manager. A `throw` is unreachable in practice (minting a
    /// JWT from a fixed payload shape cannot fail); the signature is `AuthTokenProvider`'s.
    func provide() async throws -> String {
        // Capture this call's own number up front: a held call resumes after later calls
        // have appended, so re-reading the count would mint duplicate JWT subjects.
        let (number, latch): (Int, BehaviorLatch?) = lock.withLock {
            let number = invocations.count + 1
            invocations.append(Invocation(number: number))
            return (number, latches.isEmpty ? nil : latches.removeFirst())
        }
        if let latch {
            await withTaskCancellationHandler {
                await latch.wait()
            } onCancel: {
                Task { await latch.open() }
            }
        }
        return try makeBehaviorTestJWT(subject: "auth-token-\(number)", validAt: currentDate())
    }
}

// MARK: - Manager fixture

/// An `AuthTokenManager` independent of `.shared`, following `identity` and `config` (the
/// canonical Core stores by default), on the test environment's clock, whose callers are
/// never bound by a real-time fetch budget. Uses the Task 3 internal test initializer.
func makeAuthBehaviorManager(
    identity: VersionedIdentityReading = IdentityStore.shared,
    config: ConfigReading = SDKConfigStore.shared
) -> AuthTokenManager {
    AuthTokenManager(
        lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { Empty().eraseToAnyPublisher() }),
        currentDate: { environment.date() },
        reachabilityStatus: { nil },
        identity: identity,
        fetchTimeoutSleep: behaviorNeverTimesOut,
        config: config
    )
}
