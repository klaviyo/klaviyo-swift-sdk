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
        let tokenA = try makeAuthJWT(subject: "A")

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
        let tokenB = try makeAuthJWT(subject: "B")

        sdk.unregisterAuthTokenProvider()
        sdk.registerAuthTokenProvider { tokenB }
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let currentToken = try await AuthTokenManager.shared.currentToken()
        XCTAssertEqual(currentToken, tokenB)
    }

    func testRegisterUnregisterRegisterUsesLastPublicIntent() async throws {
        let tokenA = try makeAuthJWT(subject: "A")
        let tokenB = try makeAuthJWT(subject: "B")

        sdk.registerAuthTokenProvider { tokenA }
        sdk.unregisterAuthTokenProvider()
        sdk.registerAuthTokenProvider { tokenB }
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let currentToken = try await AuthTokenManager.shared.currentToken()
        XCTAssertEqual(currentToken, tokenB)
    }
}
