//
//  AuthTokenManagerRejectedTokenTests.swift
//  KlaviyoCore
//

@testable import KlaviyoCore
import Combine
import Foundation

#if canImport(Testing)
import Testing

struct AuthTokenManagerRejectedTokenTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func replacesRejectedTokenWithOneProviderCall() async throws {
        let (rejected, replacement) = try tokens()
        let (manager, counter) = await makeManager { $0 == 1 ? rejected : replacement }
        var updates = await subscribe(to: manager)

        await manager.refreshRejectedToken()
        await manager.clearTokenState()

        let published = await publishedTokens(from: &updates)
        #expect(published == [replacement])
        let invocations = await counter.value
        #expect(invocations == 2)
    }

    @Test
    func replacementIsServedFromCacheAfterRefresh() async throws {
        let (rejected, replacement) = try tokens()
        let (manager, counter) = await makeManager { $0 == 1 ? rejected : replacement }

        await manager.refreshRejectedToken()

        let next = try await manager.currentToken(mode: .background)
        #expect(next == replacement)
        let invocations = await counter.value
        #expect(invocations == 2)
    }

    @Test
    func currentTokenDuringReplacementJoinsFetchInsteadOfServingRejectedToken() async throws {
        let (rejected, replacement) = try tokens()
        let entered = Latch()
        let release = Latch()
        let (manager, counter) = await makeManager { invocation in
            guard invocation == 2 else { return rejected }
            await entered.open()
            await release.wait()
            return replacement
        }

        let refresh = Task { await manager.refreshRejectedToken() }
        await entered.wait()
        await #expect(throws: AuthTokenError.timedOut) {
            _ = try await manager.currentToken(mode: .interactive)
        }
        await release.open()
        await refresh.value

        let next = try await manager.currentToken(mode: .background)
        #expect(next == replacement)
        let invocations = await counter.value
        #expect(invocations == 2)
    }

    @Test
    func joinsFetchStartedBeforeSignalAndPublishesItsResult() async throws {
        let (rejected, replacement) = try tokens()
        let laterToken = try makeToken(subject: "later")
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let entered = Latch()
        let release = Latch()
        let (manager, counter) = await makeManager(clock: clock, gate: gate) { invocation in
            switch invocation {
            case 1: return rejected
            case 2:
                await entered.open()
                await release.wait()
                return replacement
            default: return laterToken
            }
        }
        await gate.waitUntilSleeping()
        var updates = await subscribe(to: manager)
        clock.advance(by: 3300)
        await gate.release()
        await entered.wait()

        let refresh = Task { await manager.refreshRejectedToken() }
        await awaitCachedTokenDiscarded(manager)
        await release.open()
        await refresh.value
        await manager.clearTokenState()

        let published = await publishedTokens(from: &updates)
        #expect(!published.isEmpty)
        #expect(published.allSatisfy { $0 == replacement })
        let invocations = await counter.value
        #expect(invocations == 2)
    }

    @Test
    func offlineReplacementFailureRetriesOnceWhenConnectivityReturns() async throws {
        let (rejected, replacement) = try tokens()
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let reachability = TestReachability(.notReachable)
        let (manager, counter) = await makeManager(
            lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() }),
            reachability: reachability
        ) { invocation in
            switch invocation {
            case 1: return rejected
            case 2: throw URLError(.notConnectedToInternet)
            default: return replacement
            }
        }
        var updates = await subscribe(to: manager)

        await manager.refreshRejectedToken()
        let armed = await manager.isAwaitingConnectivityRetryForTesting
        #expect(armed)
        let offlineInvocations = await counter.value
        #expect(offlineInvocations == 2)

        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))
        let retried = await updates.next()
        guard case let .token(retriedToken)? = retried else {
            Issue.record("expected the retried token, got \(String(describing: retried))")
            return
        }
        #expect(retriedToken == replacement)
        await manager.clearTokenState()

        let laterPublished = await publishedTokens(from: &updates)
        #expect(laterPublished.isEmpty)
        let invocations = await counter.value
        #expect(invocations == 3)
    }

    @Test
    func providerFailureDiscardsRejectedTokenAndPublishesNothing() async throws {
        let (rejected, replacement) = try tokens()
        let (manager, counter) = await makeManager { invocation in
            switch invocation {
            case 1: return rejected
            case 2: throw ProviderTestError.network
            default: return replacement
            }
        }
        var updates = await subscribe(to: manager)

        await manager.refreshRejectedToken()
        let next = try await manager.currentToken(mode: .background)
        await manager.clearTokenState()

        let published = await publishedTokens(from: &updates)
        #expect(published.isEmpty)
        #expect(next == replacement)
        let invocations = await counter.value
        #expect(invocations == 3)
    }

    @Test
    func noProviderPublishesNothing() async throws {
        let manager = AuthTokenManager(lifeCycle: noopLifecycle(), currentDate: { referenceDate })
        var updates = await manager.updates().makeAsyncIterator()
        _ = await updates.next()

        await manager.refreshRejectedToken()
        await manager.clearTokenState()

        let published = await publishedTokens(from: &updates)
        #expect(published.isEmpty)
        await #expect(throws: AuthTokenError.self) {
            _ = try await manager.currentToken(mode: .background)
        }
    }

    @Test
    func providerRemovalMidRefreshPublishesNothing() async throws {
        var refresh = try await interruptMidRefresh { await $0.unregisterProvider() }
        let manager = refresh.manager

        await manager.clearTokenState()

        let published = await publishedTokens(from: &refresh.updates, untilClears: 2)
        #expect(published.isEmpty)
        await #expect(throws: AuthTokenError.self) {
            _ = try await manager.currentToken(mode: .background)
        }
    }

    @Test
    func profileResetMidRefreshPublishesNothingAndCachesNothing() async throws {
        try await expectInterruptionDropsReplacement { await $0.clearTokenState() }
    }

    @Test
    func companyChangeMidRefreshPublishesNothingAndCachesNothing() async throws {
        try await expectInterruptionDropsReplacement { manager in
            await manager.beginCompanyChange()
            await manager.completeCompanyChange()
        }
    }

    @Test
    func refreshDuringCompanyChangeDoesNotInvokeProvider() async throws {
        let (rejected, replacement) = try tokens()
        let (manager, counter) = await makeManager { $0 == 1 ? rejected : replacement }
        await manager.beginCompanyChange()

        await manager.refreshRejectedToken()

        let invocations = await counter.value
        #expect(invocations == 1)
        await manager.completeCompanyChange()
    }
}

// MARK: - Helpers

extension AuthTokenManagerRejectedTokenTests {
    private func tokens() throws -> (rejected: String, replacement: String) {
        try (makeToken(subject: "rejected"), makeToken(subject: "replacement"))
    }

    private func makeToken(subject: String) throws -> String {
        try makeJWT(
            issuedAt: referenceDate.timeIntervalSince1970 - 60,
            expiresAt: referenceDate.timeIntervalSince1970 + 3600,
            extraClaims: ["sub": subject]
        )
    }

    /// Builds a manager whose scheduled refreshes fire only when `gate` releases
    /// them, registers `token` as its provider, and waits for the first token to be
    /// cached. `clock` defaults to a fixed ``referenceDate``.
    private func makeManager(
        lifeCycle: AppLifeCycleEvents? = nil,
        clock: TestClock? = nil,
        gate: SleepGate = SleepGate(),
        reachability: TestReachability = TestReachability(),
        token: @escaping @Sendable (_ invocation: Int) async throws -> String
    ) async -> (AuthTokenManager, CallCounter) {
        let clock = clock ?? TestClock(referenceDate)
        let manager = AuthTokenManager(
            lifeCycle: lifeCycle ?? noopLifecycle(),
            currentDate: { clock.now() },
            sleep: { await gate.sleep($0) },
            reachabilityStatus: { reachability.status() }
        )
        let counter = CallCounter()
        await manager.registerProvider {
            try await token(counter.increment())
        }
        _ = try? await manager.currentToken(mode: .background)
        return (manager, counter)
    }

    /// Subscribes to `manager` and drops the replayed current state.
    private func subscribe(to manager: AuthTokenManager) async -> AsyncStream<AuthTokenUpdate>.Iterator {
        var iterator = await manager.updates().makeAsyncIterator()
        _ = await iterator.next()
        return iterator
    }

    private struct InterruptedRefresh {
        let manager: AuthTokenManager
        let counter: CallCounter
        var updates: AsyncStream<AuthTokenUpdate>.Iterator
        let laterToken: String
    }

    /// Starts a refresh whose replacement fetch blocks in the provider, runs
    /// `interruption` while it is blocked, then lets the provider return and
    /// waits for the refresh to finish. `updates` was subscribed before the
    /// refresh started; later provider calls return `laterToken`.
    private func interruptMidRefresh(
        _ interruption: @escaping (AuthTokenManager) async -> Void
    ) async throws -> InterruptedRefresh {
        let (rejected, replacement) = try tokens()
        let laterToken = try makeToken(subject: "later")
        let entered = Latch()
        let release = Latch()
        let (manager, counter) = await makeManager { invocation in
            guard invocation == 2 else { return invocation == 1 ? rejected : laterToken }
            await entered.open()
            await release.wait()
            return replacement
        }
        let updates = await subscribe(to: manager)

        let refresh = Task { await manager.refreshRejectedToken() }
        await entered.wait()
        await interruption(manager)
        await release.open()
        await refresh.value
        return InterruptedRefresh(
            manager: manager,
            counter: counter,
            updates: updates,
            laterToken: laterToken
        )
    }

    /// Expects a replacement that arrives after `interruption` to be neither
    /// published nor cached.
    private func expectInterruptionDropsReplacement(
        _ interruption: @escaping (AuthTokenManager) async -> Void
    ) async throws {
        var refresh = try await interruptMidRefresh(interruption)

        await refresh.manager.clearTokenState()

        let published = await publishedTokens(from: &refresh.updates, untilClears: 2)
        #expect(published.isEmpty)
        let next = try await refresh.manager.currentToken(mode: .background)
        #expect(next == refresh.laterToken)
        let invocations = await refresh.counter.value
        #expect(invocations == 3)
    }

    /// Waits until `manager` no longer replays a cached token.
    private func awaitCachedTokenDiscarded(
        _ manager: AuthTokenManager,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<10_000 {
            var replay = await manager.updates().makeAsyncIterator()
            if case .cleared? = await replay.next() { return }
            await Task.yield()
        }
        Issue.record("cached token was never discarded", sourceLocation: sourceLocation)
    }

    /// Collects tokens published before the `clears`-th clear, which tests send
    /// as a sentinel after the operation under test.
    private func publishedTokens(
        from updates: inout AsyncStream<AuthTokenUpdate>.Iterator,
        untilClears clears: Int = 1
    ) async -> [String] {
        var tokens: [String] = []
        var seenClears = 0
        while seenClears < clears, let update = await updates.next() {
            switch update {
            case .cleared: seenClears += 1
            case let .token(token): tokens.append(token)
            }
        }
        return tokens
    }

    private func noopLifecycle() -> AppLifeCycleEvents {
        AppLifeCycleEvents(lifeCycleEvents: { Empty().eraseToAnyPublisher() })
    }
}
#endif
