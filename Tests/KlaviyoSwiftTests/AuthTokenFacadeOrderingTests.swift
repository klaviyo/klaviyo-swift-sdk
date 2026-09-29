@testable import KlaviyoSwift
import Foundation
import KlaviyoCore
import XCTest

final class AuthTokenFacadeOrderingTests: XCTestCase {
    private var savedCoreEnvironment: KlaviyoEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        savedCoreEnvironment = environment
        environment = KlaviyoEnvironment.test()
        await AuthTokenManager.shared.unregisterProvider()
    }

    override func tearDown() async throws {
        await AuthTokenManager.shared.unregisterProvider()
        environment = savedCoreEnvironment
        try await super.tearDown()
    }

    func testRegisterUnregisterRegisterKeepsLastProvider() async throws {
        let klaviyoSDK = KlaviyoSDK()
        let tokenA = try makeToken(subject: "A")
        let tokenB = try makeToken(subject: "B")

        for iteration in 0..<100 {
            let providerBInvoked = expectation(description: "provider B invoked on iteration \(iteration)")

            klaviyoSDK.registerAuthTokenProvider { tokenA }
            klaviyoSDK.unregisterAuthTokenProvider()
            klaviyoSDK.registerAuthTokenProvider {
                providerBInvoked.fulfill()
                return tokenB
            }

            await fulfillment(of: [providerBInvoked], timeout: 2)
            let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
            XCTAssertEqual(currentToken, tokenB, "last provider wins on iteration \(iteration)")
        }
    }

    func testUnregisterThenRegisterKeepsProvider() async throws {
        let klaviyoSDK = KlaviyoSDK()
        let tokenA = try makeToken(subject: "A")
        let tokenB = try makeToken(subject: "B")

        for iteration in 0..<100 {
            let providerAInvoked = expectation(description: "provider A invoked on iteration \(iteration)")
            let providerBInvoked = expectation(description: "provider B invoked on iteration \(iteration)")

            klaviyoSDK.registerAuthTokenProvider {
                providerAInvoked.fulfill()
                return tokenA
            }
            await fulfillment(of: [providerAInvoked], timeout: 2)

            klaviyoSDK.unregisterAuthTokenProvider()
            klaviyoSDK.registerAuthTokenProvider {
                providerBInvoked.fulfill()
                return tokenB
            }

            await fulfillment(of: [providerBInvoked], timeout: 2)
            let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
            XCTAssertEqual(currentToken, tokenB, "last provider wins on iteration \(iteration)")
        }
    }

    func testRegisterThenUnregisterLeavesNoProvider() async throws {
        let klaviyoSDK = KlaviyoSDK()
        let tokenA = try makeToken(subject: "A")
        let tokenB = try makeToken(subject: "B")

        for iteration in 0..<100 {
            let providerAInvoked = expectation(description: "provider A invoked on iteration \(iteration)")

            klaviyoSDK.registerAuthTokenProvider {
                providerAInvoked.fulfill()
                return tokenA
            }
            await fulfillment(of: [providerAInvoked], timeout: 2)
            let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
            XCTAssertEqual(currentToken, tokenA, "provider A active on iteration \(iteration)")

            klaviyoSDK.registerAuthTokenProvider { tokenB }
            klaviyoSDK.unregisterAuthTokenProvider()

            try await waitForNoProvider(iteration: iteration)
        }
    }

    private func waitForNoProvider(iteration: Int) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            do {
                _ = try await AuthTokenManager.shared.currentToken(mode: .background)
            } catch AuthTokenError.noProviderRegistered {
                return
            } catch is CancellationError {}
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("provider still registered after final unregister on iteration \(iteration)")
    }

    private func makeToken(subject: String) throws -> String {
        let currentTime = environment.date().timeIntervalSince1970
        let payload = try JSONSerialization.data(withJSONObject: [
            "sub": subject,
            "iat": currentTime - 60,
            "exp": currentTime + 3600
        ])
        return [Data("{}".utf8), payload, Data(subject.utf8)]
            .map { data in
                data.base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            }
            .joined(separator: ".")
    }
}
