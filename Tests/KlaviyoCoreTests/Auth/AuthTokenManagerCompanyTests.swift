@testable import KlaviyoCore
import Foundation
#if canImport(Testing)
import Combine
import Testing

/// Config whose `publisher` never emits, so company changes are observed only
/// when the manager reads `current`. Each read of `current` is counted.
private final class SilentConfig: ConfigReading {
    private let store: SDKConfigStore
    let reads = CallCounter()

    init(initialConfig: KlaviyoConfig) {
        store = SDKConfigStore(initialConfig: initialConfig)
    }

    var current: KlaviyoConfig {
        Task { await reads.increment() }
        return store.current
    }

    var publisher: AnyPublisher<KlaviyoConfig, Never> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    func stream() -> AsyncStream<KlaviyoConfig> {
        AsyncStream { _ in }
    }

    func update(_ config: KlaviyoConfig) {
        store.update(config)
    }
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
        let config = SilentConfig(initialConfig: KlaviyoConfig(apiKey: "A"))

        let tokenA = try makeJWT(extraClaims: ["sub": "A"])
        let releaseFetch = Latch()
        let calls = CallCounter()
        let manager = AuthTokenManager(currentDate: { Date() }, config: config)
        await manager.registerProvider {
            _ = await calls.increment()
            await releaseFetch.wait()
            return tokenA
        }
        try await calls.waitFor(atLeast: 1)

        let caller = Task { try await manager.currentToken(mode: .interactive) }
        try await config.reads.waitFor(atLeast: 3)

        config.update(KlaviyoConfig(apiKey: "B"))
        await releaseFetch.open()

        await #expect(throws: AuthTokenError.companyChanged) {
            try await withTimeout(seconds: 2) { try await caller.value }
        }
        await manager.unregisterProvider()
    }
}
#endif
