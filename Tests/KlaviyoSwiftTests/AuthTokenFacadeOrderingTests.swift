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
        let tokenB = try makeToken(subject: "B")
        try await assertLastProviderWins(expecting: tokenB) { klaviyoSDK, tokenA, register in
            klaviyoSDK.registerAuthTokenProvider { tokenA }
            klaviyoSDK.unregisterAuthTokenProvider()
            register(klaviyoSDK)
        }
    }

    func testUnregisterThenRegisterKeepsProvider() async throws {
        let tokenB = try makeToken(subject: "B")
        try await assertLastProviderWins(expecting: tokenB) { klaviyoSDK, _, register in
            klaviyoSDK.unregisterAuthTokenProvider()
            register(klaviyoSDK)
        }
    }

    func testRegisterThenUnregisterLeavesNoProvider() async throws {
        let klaviyoSDK = KlaviyoSDK()
        let tokenA = try makeToken(subject: "A")

        for iteration in 0..<100 {
            klaviyoSDK.registerAuthTokenProvider { tokenA }
            klaviyoSDK.unregisterAuthTokenProvider()

            try await waitForNoProvider(iteration: iteration)
        }
    }

    /// Runs `calls` 100 times, then asserts the provider registered last is the one in effect.
    private func assertLastProviderWins(
        expecting expectedToken: String,
        calls: (KlaviyoSDK, _ tokenA: String, _ registerLast: (KlaviyoSDK) -> Void) -> Void
    ) async throws {
        let klaviyoSDK = KlaviyoSDK()
        let tokenA = try makeToken(subject: "A")

        for iteration in 0..<100 {
            let providerBInvoked = expectation(description: "provider B invoked on iteration \(iteration)")

            calls(klaviyoSDK, tokenA) { klaviyoSDK in
                klaviyoSDK.registerAuthTokenProvider {
                    providerBInvoked.fulfill()
                    return expectedToken
                }
            }

            await fulfillment(of: [providerBInvoked], timeout: 2)
            let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
            XCTAssertEqual(currentToken, expectedToken, "last provider wins on iteration \(iteration)")
        }
    }

    private func waitForNoProvider(iteration: Int) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            do {
                _ = try await AuthTokenManager.shared.currentToken(mode: .background)
            } catch AuthTokenError.noProviderRegistered {
                return
            }
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
