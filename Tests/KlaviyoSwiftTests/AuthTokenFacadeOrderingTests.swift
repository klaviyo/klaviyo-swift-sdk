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

    @MainActor
    func testResetClearsCachedTokenBeforePublishingActionAndRetainsProvider() async throws {
        let savedSwiftEnvironment = klaviyoSwiftEnvironment
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        defer { klaviyoSwiftEnvironment = savedSwiftEnvironment }

        let tokenA = try makeToken(subject: "before-reset")
        let tokenB = try makeToken(subject: "after-reset")
        let nextToken = LockedBox(tokenA)
        await AuthTokenManager.shared.registerProvider { nextToken.get() }
        let cached = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(cached, tokenA)
        nextToken.set(tokenB)

        let observedAtSend = LockedBox<String?>(nil)
        let actionSent = expectation(description: "reset action published")
        klaviyoSwiftEnvironment.send = { action in
            guard case .resetProfile = action else { return nil }
            let finished = DispatchSemaphore(value: 0)
            Task.detached {
                let token = try? await AuthTokenManager.shared.currentToken(mode: .background)
                observedAtSend.set(token)
                finished.signal()
            }
            XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
            actionSent.fulfill()
            return nil
        }

        KlaviyoSDK().resetProfile()
        await fulfillment(of: [actionSent], timeout: 3)
        XCTAssertEqual(observedAtSend.get(), tokenB)
        await AuthTokenManager.shared.unregisterProvider()
    }

    @MainActor
    func testResetCancelsInFlightTokenBeforePublishingActionAndRetainsProvider() async throws {
        let savedSwiftEnvironment = klaviyoSwiftEnvironment
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        defer { klaviyoSwiftEnvironment = savedSwiftEnvironment }

        let tokenA = try makeToken(subject: "before-reset")
        let tokenB = try makeToken(subject: "after-reset")
        let calls = LockedBox(0)
        let cancelled = LockedBox(false)
        let firstStarted = expectation(description: "first provider call started")
        await AuthTokenManager.shared.registerProvider {
            let call = calls.update { $0 += 1; return $0 }
            guard call == 1 else { return tokenB }
            return try await withTaskCancellationHandler {
                firstStarted.fulfill()
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return tokenA
            } onCancel: {
                cancelled.set(true)
            }
        }
        await fulfillment(of: [firstStarted], timeout: 3)

        let cancelledAtSend = LockedBox(false)
        let actionSent = expectation(description: "reset action published")
        klaviyoSwiftEnvironment.send = { action in
            guard case .resetProfile = action else { return nil }
            cancelledAtSend.set(cancelled.get())
            actionSent.fulfill()
            return nil
        }

        KlaviyoSDK().resetProfile()
        await fulfillment(of: [actionSent], timeout: 3)
        XCTAssertTrue(cancelledAtSend.get())
        let current = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(current, tokenB)
        await AuthTokenManager.shared.unregisterProvider()
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

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func update<Result>(_ transform: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return transform(&value)
    }
}
