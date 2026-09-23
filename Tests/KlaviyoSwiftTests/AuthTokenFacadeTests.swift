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

    func testResetQueuesClearBeforeLaterRegistration() async throws {
        let tokenB = try makeAuthJWT(subject: "B")
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
        let effectGate = DispatchEffectGate()
        let effect = Task {
            await effectGate.wait()
        }
        defer {
            effect.cancel()
            klaviyoSwiftEnvironment.send = originalSend
        }
        let sendObserved = expectation(description: "reducer send observed")
        klaviyoSwiftEnvironment.send = { action in
            guard action == .start else { return nil }
            sendObserved.fulfill()
            return effect
        }

        let completion = expectation(description: "dispatch completes after reducer send")
        let dispatch = dispatchOnMainThread(action: .start)
        Task {
            await dispatch.value
            completion.fulfill()
        }
        await fulfillment(of: [sendObserved, completion], timeout: 2)
        await effectGate.open()
        await effect.value
    }
}

private actor DispatchEffectGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
