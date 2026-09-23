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
        let tokenA = try makeAuthJWT(subject: "A")

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
        let tokenB = try makeAuthJWT(subject: "B")

        klaviyoSDK.unregisterAuthTokenProvider()
        klaviyoSDK.registerAuthTokenProvider { tokenB }
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(currentToken, tokenB)
    }

    func testRegisterUnregisterRegisterUsesLastPublicIntent() async throws {
        let tokenA = try makeAuthJWT(subject: "A")
        let tokenB = try makeAuthJWT(subject: "B")

        klaviyoSDK.registerAuthTokenProvider { tokenA }
        klaviyoSDK.unregisterAuthTokenProvider()
        klaviyoSDK.registerAuthTokenProvider { tokenB }
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(currentToken, tokenB)
    }
}
