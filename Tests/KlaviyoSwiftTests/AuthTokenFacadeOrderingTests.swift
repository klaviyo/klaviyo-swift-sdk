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
        IdentityStore.shared.update(ProfileData(email: "user@example.com"))
        await AuthTokenManager.shared.unregisterProvider()
    }

    override func tearDown() async throws {
        await AuthTokenManager.shared.unregisterProvider()
        IdentityStore.shared.update(ProfileData())
        environment = savedCoreEnvironment
        try await super.tearDown()
    }

    func testRegisterUnregisterRegisterKeepsLastProvider() async throws {
        let klaviyoSDK = KlaviyoSDK()
        let tokenA = try makeToken(subject: "A")

        for iteration in 0..<100 {
            let tokenB = try makeToken(subject: "B-\(iteration)")
            klaviyoSDK.registerAuthTokenProvider { tokenA }
            klaviyoSDK.unregisterAuthTokenProvider()
            klaviyoSDK.registerAuthTokenProvider { tokenB }

            try await waitForToken(tokenB, iteration: iteration)
        }
    }

    func testUnregisterThenRegisterKeepsProvider() async throws {
        let klaviyoSDK = KlaviyoSDK()

        for iteration in 0..<100 {
            let tokenA = try makeToken(subject: "A-\(iteration)")
            let tokenB = try makeToken(subject: "B-\(iteration)")
            klaviyoSDK.registerAuthTokenProvider { tokenA }
            try await waitForToken(tokenA, iteration: iteration)

            klaviyoSDK.unregisterAuthTokenProvider()
            klaviyoSDK.registerAuthTokenProvider { tokenB }

            try await waitForToken(tokenB, iteration: iteration)
        }
    }

    func testRegisterThenUnregisterLeavesNoProvider() async throws {
        let klaviyoSDK = KlaviyoSDK()
        let tokenB = try makeToken(subject: "B")

        for iteration in 0..<100 {
            let tokenA = try makeToken(subject: "A-\(iteration)")
            klaviyoSDK.registerAuthTokenProvider { tokenA }
            try await waitForToken(tokenA, iteration: iteration)

            klaviyoSDK.registerAuthTokenProvider { tokenB }
            klaviyoSDK.unregisterAuthTokenProvider()

            try await waitForNoProvider(iteration: iteration)
        }
    }

    private func waitForToken(_ expectedToken: String, iteration: Int) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            do {
                let currentToken = try await AuthTokenManager.shared.currentToken(mode: .interactive)
                if currentToken == expectedToken {
                    return
                }
            } catch AuthTokenError.noProviderRegistered {
            } catch AuthTokenError.timedOut {
            } catch is CancellationError {}
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("expected provider token not active on iteration \(iteration)")
    }

    private func waitForNoProvider(iteration: Int) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            do {
                _ = try await AuthTokenManager.shared.currentToken(mode: .interactive)
            } catch AuthTokenError.noProviderRegistered {
                return
            } catch AuthTokenError.timedOut {
            } catch is CancellationError {}
            try await Task.sleep(nanoseconds: 10_000_000)
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
