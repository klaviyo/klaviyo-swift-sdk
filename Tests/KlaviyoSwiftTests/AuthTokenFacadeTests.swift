//
//  AuthTokenFacadeTests.swift
//  KlaviyoSwiftTests
//

@testable import KlaviyoSwift
import Foundation
import KlaviyoCore
import XCTest

final class AuthTokenFacadeTests: XCTestCase {
    private let klaviyoSDK = KlaviyoSDK()

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        klaviyoSDK.unregisterAuthTokenProvider()
        await AuthTokenCommandQueue.shared.waitForPendingCommands()
    }

    override func tearDown() async throws {
        klaviyoSDK.unregisterAuthTokenProvider()
        await AuthTokenCommandQueue.shared.waitForPendingCommands()
        try await super.tearDown()
    }

    func testRegisterThenUnregisterUsesLastPublicIntent() async throws {
        let tokenA = try makeJWT(subject: "A")

        klaviyoSDK.registerAuthTokenProvider { tokenA }
        klaviyoSDK.unregisterAuthTokenProvider()
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        do {
            _ = try await AuthTokenManager.shared.currentToken()
            XCTFail("Expected no provider to remain registered")
        } catch {
            XCTAssertEqual(error as? AuthTokenError, .noProviderRegistered)
        }
    }

    func testUnregisterThenRegisterUsesLastPublicIntent() async throws {
        let tokenB = try makeJWT(subject: "B")

        klaviyoSDK.unregisterAuthTokenProvider()
        klaviyoSDK.registerAuthTokenProvider { tokenB }
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(currentToken, tokenB)
    }

    func testRegisterUnregisterRegisterUsesLastPublicIntent() async throws {
        let tokenA = try makeJWT(subject: "A")
        let tokenB = try makeJWT(subject: "B")

        klaviyoSDK.registerAuthTokenProvider { tokenA }
        klaviyoSDK.unregisterAuthTokenProvider()
        klaviyoSDK.registerAuthTokenProvider { tokenB }
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(currentToken, tokenB)
    }

    func testResetQueuesClearBeforeLaterRegistration() async throws {
        let tokenB = try makeJWT(subject: "B")
        let revision = AuthTokenCommandQueue.shared.revision

        klaviyoSDK.resetProfile()
        XCTAssertGreaterThan(AuthTokenCommandQueue.shared.revision, revision)
        klaviyoSDK.registerAuthTokenProvider { tokenB }
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(currentToken, tokenB)
    }

    func testGenericDispatchDoesNotWaitForLongLivedEffect() async {
        let originalSend = klaviyoSwiftEnvironment.send
        let effect = Task {
            _ = try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        defer {
            effect.cancel()
            klaviyoSwiftEnvironment.send = originalSend
        }
        klaviyoSwiftEnvironment.send = { action in
            guard action == .start else { return nil }
            return effect
        }

        let completion = expectation(description: "dispatch completes after reducer send")
        let dispatch = dispatchOnMainThread(action: .start)
        Task {
            await dispatch.value
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 0.3)
    }

    private func makeJWT(subject: String) throws -> String {
        let timestamp = environment.date().timeIntervalSince1970
        let payload = try JSONSerialization.data(withJSONObject: [
            "sub": subject,
            "iat": timestamp - 60,
            "exp": timestamp + 3600
        ])
        return [Data("{}".utf8), payload, Data(subject.utf8)]
            .map(base64URLEncode)
            .joined(separator: ".")
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
