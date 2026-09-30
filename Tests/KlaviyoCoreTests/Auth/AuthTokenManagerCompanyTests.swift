@testable import KlaviyoCore
import Foundation
#if canImport(Testing)
import Combine
import Testing

/// Config backed by a real `SDKConfigStore` that counts reads of `current`.
/// With `publishes: false` the publisher never emits, so the manager observes
/// company changes only when it reads `current` itself.
private final class ReadCountingConfig: ConfigReading {
    private let store: SDKConfigStore
    private let publishes: Bool
    private let lock = NSLock()
    private var count = 0
    private var waiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(initialConfig: KlaviyoConfig, publishes: Bool = true) {
        store = SDKConfigStore(initialConfig: initialConfig)
        self.publishes = publishes
    }

    var current: KlaviyoConfig {
        lock.lock()
        count += 1
        let ready = waiters.filter { count >= $0.threshold }
        waiters.removeAll { count >= $0.threshold }
        lock.unlock()
        ready.forEach { $0.continuation.resume() }
        return store.current
    }

    var publisher: AnyPublisher<KlaviyoConfig, Never> {
        publishes ? store.publisher : Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    func stream() -> AsyncStream<KlaviyoConfig> {
        AsyncStream { _ in }
    }

    func update(_ config: KlaviyoConfig) {
        store.update(config)
    }

    func waitForReads(atLeast threshold: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if count >= threshold {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append((threshold, continuation))
                lock.unlock()
            }
        }
    }
}

/// Registers a provider that counts invocations, optionally blocks on `gate`,
/// and returns `token`.
private func registerCountingProvider(
    on manager: AuthTokenManager,
    returning token: String,
    gate: Latch? = nil
) async -> CallCounter {
    let calls = CallCounter()
    await manager.registerProvider {
        _ = await calls.increment()
        await gate?.wait()
        return token
    }
    return calls
}

@Suite(.serialized)
struct AuthTokenManagerCompanyTests {
    @Test
    func companyChangeInvalidatesCachedTokenAndRetainsProvider() async throws {
        let config = SDKConfigStore(initialConfig: KlaviyoConfig(apiKey: "A"))

        let tokenA = try makeJWT(extraClaims: ["sub": "A"])
        let tokenB = try makeJWT(extraClaims: ["sub": "B"])
        let providerToken = TokenBox(tokenA)
        let calls = CallCounter()
        let manager = AuthTokenManager(currentDate: { Date() }, config: config)
        await manager.registerProvider {
            _ = await calls.increment()
            return await providerToken.value
        }

        let cachedA = try await manager.currentToken(mode: .background)
        #expect(cachedA == tokenA)

        await providerToken.set(tokenB)
        config.update(KlaviyoConfig(apiKey: "B"))

        let current = try await manager.currentToken(mode: .background)
        let callCount = await calls.value
        #expect(current == tokenB)
        #expect(callCount == 2)
        await manager.unregisterProvider()
    }

    @Test
    func sameCompanyUpdateKeepsCachedToken() async throws {
        let config = SDKConfigStore(initialConfig: KlaviyoConfig(apiKey: "A"))

        let tokenA = try makeJWT(extraClaims: ["sub": "A"])
        let tokenB = try makeJWT(extraClaims: ["sub": "B"])
        let providerToken = TokenBox(tokenA)
        let calls = CallCounter()
        let manager = AuthTokenManager(currentDate: { Date() }, config: config)
        await manager.registerProvider {
            _ = await calls.increment()
            return await providerToken.value
        }
        let cachedA = try await manager.currentToken(mode: .background)
        #expect(cachedA == tokenA)

        await providerToken.set(tokenB)
        config.update(KlaviyoConfig(apiKey: "A"))

        let current = try await manager.currentToken(mode: .background)
        let callCount = await calls.value
        #expect(current == tokenA)
        #expect(callCount == 1)
        await manager.unregisterProvider()
    }

    @Test
    func companyChangeCancelsInFlightToken() async throws {
        let config = SDKConfigStore(initialConfig: KlaviyoConfig(apiKey: "A"))

        let tokenA = try makeJWT(extraClaims: ["sub": "A"])
        let tokenB = try makeJWT(extraClaims: ["sub": "B"])
        let releaseFirst = Latch()
        let (cancellations, cancellationContinuation) = AsyncStream.makeStream(of: Void.self)
        let calls = CallCounter()
        let manager = AuthTokenManager(currentDate: { Date() }, config: config)
        await manager.registerProvider {
            let invocation = await calls.increment()
            if invocation == 1 {
                return await withTaskCancellationHandler {
                    await releaseFirst.wait()
                    return tokenA
                } onCancel: {
                    cancellationContinuation.yield(())
                }
            }
            return tokenB
        }
        try await calls.waitFor(atLeast: 1)

        config.update(KlaviyoConfig(apiKey: "B"))
        let cancellation: Void? = try await withTimeout(seconds: 2) {
            await cancellations.first { _ in true }
        }
        #expect(cancellation != nil)

        let current = try await manager.currentToken(mode: .background)
        let callCount = await calls.value
        #expect(current == tokenB)
        #expect(callCount == 2)
        await releaseFirst.open()
        await manager.unregisterProvider()
    }

    @Test
    func companyChangeDuringFetchThrowsCompanyChanged() async throws {
        let config = ReadCountingConfig(initialConfig: KlaviyoConfig(apiKey: "A"), publishes: false)

        let tokenA = try makeJWT(extraClaims: ["sub": "A"])
        let releaseFetch = Latch()
        let manager = AuthTokenManager(currentDate: { Date() }, config: config)
        let calls = await registerCountingProvider(on: manager, returning: tokenA, gate: releaseFetch)
        try await calls.waitFor(atLeast: 1)

        let caller = Task { try await manager.currentToken(mode: .interactive) }
        await config.waitForReads(atLeast: 3)

        config.update(KlaviyoConfig(apiKey: "B"))
        await releaseFetch.open()

        await #expect(throws: AuthTokenError.companyChanged) {
            try await withTimeout(seconds: 2) { try await caller.value }
        }
        await manager.unregisterProvider()
    }

    @Test
    func firstCompanyKeyKeepsWarmUpToken() async throws {
        let config = ReadCountingConfig(initialConfig: KlaviyoConfig(apiKey: nil))

        let warmUpToken = try makeJWT(extraClaims: ["sub": "warm-up"])
        let releaseWarmUp = Latch()
        let manager = AuthTokenManager(currentDate: { Date() }, config: config)
        let calls = await registerCountingProvider(on: manager, returning: warmUpToken, gate: releaseWarmUp)
        try await calls.waitFor(atLeast: 1)
        await releaseWarmUp.open()
        // Reads so far: init, warm-up request start, warm-up request end, sink's initial emission.
        await config.waitForReads(atLeast: 4)

        config.update(KlaviyoConfig(apiKey: "A"))
        await config.waitForReads(atLeast: 5)

        let current = try await manager.currentToken(mode: .background)
        let callCount = await calls.value
        #expect(current == warmUpToken)
        #expect(callCount == 1)
        await manager.unregisterProvider()
    }
}
#endif
