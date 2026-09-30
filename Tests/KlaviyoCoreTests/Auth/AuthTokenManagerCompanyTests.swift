@testable import KlaviyoCore
import Foundation
import Testing

@Suite(.serialized)
struct AuthTokenManagerCompanyTests {
    @Test
    func companyChangeInvalidatesCachedTokenAndRetainsProvider() async throws {
        let previousConfig = SDKConfigStore.shared.current
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "A"))
        defer { SDKConfigStore.shared.update(previousConfig) }

        let tokenA = try makeJWT(extraClaims: ["sub": "A"])
        let tokenB = try makeJWT(extraClaims: ["sub": "B"])
        let providerToken = TokenBox(tokenA)
        let calls = CallCounter()
        let manager = AuthTokenManager()
        await manager.registerProvider {
            _ = await calls.increment()
            return await providerToken.value
        }

        let cachedA = try await manager.currentToken(mode: .background)
        #expect(cachedA == tokenA)

        await providerToken.set(tokenB)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "B"))

        let current = try await manager.currentToken(mode: .background)
        let callCount = await calls.value
        #expect(current == tokenB)
        #expect(callCount == 2)
        await manager.unregisterProvider()
    }

    @Test
    func sameCompanyUpdateKeepsCachedToken() async throws {
        let previousConfig = SDKConfigStore.shared.current
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "A"))
        defer { SDKConfigStore.shared.update(previousConfig) }

        let tokenA = try makeJWT(extraClaims: ["sub": "A"])
        let tokenB = try makeJWT(extraClaims: ["sub": "B"])
        let providerToken = TokenBox(tokenA)
        let calls = CallCounter()
        let manager = AuthTokenManager()
        await manager.registerProvider {
            _ = await calls.increment()
            return await providerToken.value
        }
        let cachedA = try await manager.currentToken(mode: .background)
        #expect(cachedA == tokenA)

        await providerToken.set(tokenB)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "A"))

        let current = try await manager.currentToken(mode: .background)
        let callCount = await calls.value
        #expect(current == tokenA)
        #expect(callCount == 1)
        await manager.unregisterProvider()
    }

    @Test
    func companyChangeCancelsInFlightToken() async throws {
        let previousConfig = SDKConfigStore.shared.current
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "A"))
        defer { SDKConfigStore.shared.update(previousConfig) }

        let tokenA = try makeJWT(extraClaims: ["sub": "A"])
        let tokenB = try makeJWT(extraClaims: ["sub": "B"])
        let releaseFirst = Latch()
        let (cancellations, cancellationContinuation) = AsyncStream.makeStream(of: Void.self)
        let calls = CallCounter()
        let manager = AuthTokenManager()
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

        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "B"))
        let cancellation = try await withTimeout(seconds: 2) {
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
}
