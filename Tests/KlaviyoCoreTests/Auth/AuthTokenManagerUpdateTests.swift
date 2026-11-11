@testable import KlaviyoCore
import XCTest

final class AuthTokenManagerUpdateTests: XCTestCase {
    func testLateInitialFetchPublishesToExistingSubscriberAfterTimeout() async throws {
        let manager = AuthTokenManager(currentDate: Date.init,
                                       config: SDKConfigStore(initialConfig: KlaviyoConfig(apiKey: "A")))
        let token = try makeJWT()
        let entered = Latch()
        let release = Latch()
        await manager.registerProvider {
            await entered.open()
            await release.wait()
            return token
        }
        await entered.wait()
        let stream = await manager.updates()
        let received = expectation(description: "late initial token published")
        let observer = Task {
            for await update in stream {
                if case let .token(value) = update, value == token {
                    received.fulfill()
                    return
                }
            }
        }
        defer { observer.cancel() }
        do {
            _ = try await manager.currentToken(mode: .interactive)
            XCTFail("expected interactive timeout")
        } catch AuthTokenError.timedOut {}
        await release.open()
        let fetched = try await manager.currentToken(mode: .background)
        XCTAssertEqual(fetched, token)
        await fulfillment(of: [received], timeout: 2)
        await manager.unregisterProvider()
    }

    func testResetClearsRetainedSubscriberAndKeepsProvider() async throws {
        let config = SDKConfigStore(initialConfig: KlaviyoConfig(apiKey: "A"))
        let manager = AuthTokenManager(currentDate: Date.init, config: config)
        let tokenA = try makeJWT(extraClaims: ["sub": "before-reset"])
        let tokenB = try makeJWT(extraClaims: ["sub": "after-reset"])
        let calls = CallCounter()
        await manager.registerProvider {
            let call = await calls.increment()
            return call == 1 ? tokenA : tokenB
        }
        let currentA = try await manager.currentToken(mode: .background)
        XCTAssertEqual(currentA, tokenA)

        let updates = await manager.updates()
        var iterator = updates.makeAsyncIterator()
        guard case let .token(replayed) = await iterator.next() else {
            return XCTFail("expected cached token replay")
        }
        XCTAssertEqual(replayed, tokenA)

        await manager.clearTokenState()
        guard case .cleared = await iterator.next() else {
            return XCTFail("expected reset removal")
        }
        let currentB = try await manager.currentToken(mode: .background)
        XCTAssertEqual(currentB, tokenB)
    }
}
