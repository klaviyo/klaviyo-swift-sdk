//
//  AuthTokenFacadeTests.swift
//  KlaviyoSwiftTests
//

@testable import KlaviyoSwift
import Foundation
import KlaviyoCore
import XCTest

final class AuthTokenFacadeTests: XCTestCase {
    private let sdk = KlaviyoSDK()

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        sdk.unregisterAuthTokenProvider()
        await AuthTokenCommandQueue.shared.waitForPendingCommands()
    }

    override func tearDown() async throws {
        sdk.unregisterAuthTokenProvider()
        await AuthTokenCommandQueue.shared.waitForPendingCommands()
        try await super.tearDown()
    }

    func testRegisterThenUnregisterUsesLastPublicIntent() async throws {
        let tokenA = try makeJWT(subject: "A")

        sdk.registerAuthTokenProvider { tokenA }
        sdk.unregisterAuthTokenProvider()
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

        sdk.unregisterAuthTokenProvider()
        sdk.registerAuthTokenProvider { tokenB }
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let currentToken = try await AuthTokenManager.shared.currentToken()
        XCTAssertEqual(currentToken, tokenB)
    }

    func testRegisterUnregisterRegisterUsesLastPublicIntent() async throws {
        let tokenA = try makeJWT(subject: "A")
        let tokenB = try makeJWT(subject: "B")

        sdk.registerAuthTokenProvider { tokenA }
        sdk.unregisterAuthTokenProvider()
        sdk.registerAuthTokenProvider { tokenB }
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let currentToken = try await AuthTokenManager.shared.currentToken()
        XCTAssertEqual(currentToken, tokenB)
    }

    private func makeJWT(subject: String) throws -> String {
        let now = environment.date().timeIntervalSince1970
        let payload = try JSONSerialization.data(withJSONObject: [
            "sub": subject,
            "iat": now - 60,
            "exp": now + 3600
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
