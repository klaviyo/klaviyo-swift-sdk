//
//  IAFPresentationManagerOverlapTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import KlaviyoCore
import XCTest

/// Overlapping `createFormWebViewAndListen` calls: the latest call wins.
@MainActor
final class IAFPresentationManagerOverlapTests: XCTestCase {
    private actor Gate {
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

    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
        IdentityStore.shared.reset()
        SDKConfigStore.shared.reset()
        IAFPresentationManager.shared.destroyWebviewAndListeners()
    }

    override func tearDown() {
        IAFPresentationManager.shared.destroyWebviewAndListeners()
        IdentityStore.shared.reset()
        SDKConfigStore.shared.reset()
        super.tearDown()
    }

    func testOverlappingCreateCallsOnlyLatestInstallsWebView() async throws {
        let manager = IAFPresentationManager.shared
        let gate = Gate()
        let counter = InvocationCounter()
        let token = try makeTestJWT()
        await AuthTokenManager.shared.registerProvider {
            await counter.increment()
            await gate.wait()
            return token
        }

        let first = Task { try await manager.createFormWebViewAndListen(apiKey: "first-key") }
        await counter.waitFor(atLeast: 1)
        let second = Task { try await manager.createFormWebViewAndListen(apiKey: "second-key") }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(manager.viewModel, "Nothing should be built while the token fetch is pending")

        await gate.open()
        let firstCreated = try await first.value
        let secondCreated = try await second.value

        XCTAssertFalse(firstCreated)
        XCTAssertTrue(secondCreated)
        XCTAssertEqual(manager.viewModel?.apiKey, "second-key")
        XCTAssertNotNil(manager.viewController)

        await AuthTokenManager.shared.unregisterProvider()
    }
}
