//
//  IAFPresentationManagerOverlapTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import Combine
import KlaviyoCore
import WebKit
import XCTest

/// Covers `createFormWebViewAndListen` builds that overlap across the auth-token fetch,
/// rebuilds while an older handshake is still pending, and unregistering mid-build.
@MainActor
final class IAFPresentationManagerOverlapTests: XCTestCase {
    /// Covers the immediate handshake-failure path (deallocated view controller).
    private static let shortObservationWindow: TimeInterval = 1

    /// Longer than the handshake timeout (`NetworkSession.networkTimeout`), so a stale
    /// handshake timing out is also covered.
    private static let handshakeTimeoutObservationWindow: TimeInterval =
        .init(NetworkSession.networkTimeout) / 1_000_000_000 + 2

    private let gate = Latch()
    private var manager: IAFPresentationManager {
        .shared
    }

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        IdentityStore.shared.reset()
        SDKConfigStore.shared.reset()
        await AuthTokenManager.shared.unregisterProvider()
        IAFPresentationManager.shared.destroyWebviewAndListeners()
    }

    override func tearDown() async throws {
        await gate.open()
        await AuthTokenManager.shared.unregisterProvider()
        IAFPresentationManager.shared.destroyWebviewAndListeners()
        IdentityStore.shared.reset()
        SDKConfigStore.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Helpers

    private var activeViewModel: IAFWebViewModel? {
        Mirror(reflecting: manager).descendant("viewModel") as? IAFWebViewModel
    }

    private var lastBackgrounded: Date? {
        Mirror(reflecting: manager).descendant("lastBackgrounded") as? Date
    }

    /// Polls `condition` until it holds or `timeout` elapses; returns its final value.
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    /// Registers a token provider that blocks on `gate`, and waits until the eager
    /// warm-up fetch is parked on it. Later `currentToken()` callers share that fetch.
    private func registerGatedProvider() async throws {
        let gate = gate
        let counter = InvocationCounter()
        let token = try makeTestJWT()
        await AuthTokenManager.shared.registerProvider {
            await counter.increment()
            await gate.wait()
            return token
        }
        await counter.waitFor(atLeast: 1)
    }

    private func startBuild(apiKey: String) -> Task<Bool, Error> {
        Task { try await manager.createFormWebViewAndListen(apiKey: apiKey) }
    }

    /// Simulates KlaviyoJS completing the handshake on the active webview, so the
    /// active build's own handshake cannot time out during observation.
    private func completeActiveHandshake() {
        activeViewModel?.handleScriptMessage(
            MockWKScriptMessage(name: "KlaviyoNativeBridge", body: #"{"type":"handShook","data":{}}"#)
        )
    }

    /// Polls `viewController` for `window` seconds; returns the elapsed time at which
    /// it was first observed nil, or `nil` if it survived the whole window.
    private func observeTeardown(for window: TimeInterval) async -> TimeInterval? {
        let start = Date()
        while Date().timeIntervalSince(start) < window {
            if manager.viewController == nil {
                return Date().timeIntervalSince(start)
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return manager.viewController == nil ? Date().timeIntervalSince(start) : nil
    }

    private func assertActiveWebViewSurvives(
        apiKey: String,
        for window: TimeInterval = shortObservationWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        guard manager.viewController != nil else {
            XCTFail("Active webview was torn down before observation began", file: file, line: line)
            return
        }
        completeActiveHandshake()
        let teardownAt = await observeTeardown(for: window)
        let elapsed = teardownAt.map { String(format: "%.3fs", $0) } ?? "-"
        XCTAssertNil(
            teardownAt,
            "Active webview was torn down \(elapsed) after build",
            file: file,
            line: line
        )
        XCTAssertEqual(activeViewModel?.apiKey, apiKey, file: file, line: line)
    }

    private func settle(nanoseconds: UInt64 = 100_000_000) async {
        for _ in 0..<50 {
            await Task.yield()
        }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: - Tests

    func testLoneGatedBuildInstallsAndSurvives() async throws {
        try await registerGatedProvider()

        let build = startBuild(apiKey: "only-key")
        await settle()
        XCTAssertNil(manager.viewController, "Build should be parked on the token fetch")

        await gate.open()
        let installed = try await build.value

        XCTAssertTrue(installed)
        await assertActiveWebViewSurvives(apiKey: "only-key")
    }

    func testOverlappingBuildsInstallOnlyLatestAndKeepItAlive() async throws {
        try await registerGatedProvider()

        let first = startBuild(apiKey: "first-key")
        await settle(nanoseconds: 50_000_000)
        let second = startBuild(apiKey: "second-key")
        await settle()
        XCTAssertNil(manager.viewController, "Both builds should be parked on the token fetch")

        await gate.open()
        let firstInstalled = try await first.value
        let secondInstalled = try await second.value

        XCTAssertFalse(firstInstalled)
        XCTAssertTrue(secondInstalled)
        await assertActiveWebViewSurvives(apiKey: "second-key")
    }

    func testAPIKeyChangeDuringGatedTokenFetchKeepsLatestWebViewAlive() async throws {
        try await registerGatedProvider()

        manager.initializeIAF(configuration: InAppFormsConfig())
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "first-key"))
        await settle(nanoseconds: 50_000_000)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "second-key"))
        await settle()
        XCTAssertNil(manager.viewController, "Both builds should be parked on the token fetch")

        await gate.open()
        let deadline = Date().addingTimeInterval(2)
        while activeViewModel?.apiKey != "second-key", Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        await settle()

        await assertActiveWebViewSurvives(apiKey: "second-key")
    }

    func testRebuildAfterTeardownSurvivesStaleHandshakeTimeout() async throws {
        try await manager.createFormWebViewAndListen(apiKey: "first-key")
        XCTAssertNotNil(manager.viewController)
        await settle(nanoseconds: 50_000_000)

        manager.tearDownFormWebView()
        try await manager.createFormWebViewAndListen(apiKey: "second-key")
        await settle(nanoseconds: 50_000_000)

        await assertActiveWebViewSurvives(
            apiKey: "second-key",
            for: Self.handshakeTimeoutObservationWindow
        )
    }

    func testUnregisterDuringPendingBuildPreventsInstall() async throws {
        try await registerGatedProvider()

        let build = startBuild(apiKey: "first-key")
        await settle()
        manager.destroyWebviewAndListeners()

        await gate.open()
        let installed = try await build.value
        await settle()

        XCTAssertFalse(installed)
        XCTAssertNil(manager.viewController)
        XCTAssertNil(activeViewModel)
    }

    func testRebuildAfterUnregisterDuringPendingBuildInstallsOnlyLatest() async throws {
        try await registerGatedProvider()

        let first = startBuild(apiKey: "first-key")
        await settle(nanoseconds: 50_000_000)
        manager.destroyWebviewAndListeners()
        let second = startBuild(apiKey: "second-key")
        await settle()
        XCTAssertNil(manager.viewController, "Both builds should be parked on the token fetch")

        await gate.open()
        let firstInstalled = try await first.value
        let secondInstalled = try await second.value

        XCTAssertFalse(firstInstalled)
        XCTAssertTrue(secondInstalled)
        await assertActiveWebViewSurvives(apiKey: "second-key")
    }

    func testForegroundRebuildDuringAPIKeyChangeKeepsLifecycleObservationAlive() async throws {
        let lifecycleEvents = PassthroughSubject<LifeCycleEvents, Never>()
        environment.appLifeCycle = AppLifeCycleEvents(lifeCycleEvents: {
            lifecycleEvents.eraseToAnyPublisher()
        })

        manager.initializeIAF(configuration: InAppFormsConfig())
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "first-key"))
        let firstInstalled = await waitUntil { self.activeViewModel?.apiKey == "first-key" }
        XCTAssertTrue(firstInstalled)
        XCTAssertNil(lastBackgrounded)

        try await registerGatedProvider()
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "second-key"))
        await settle()
        XCTAssertNil(manager.viewController, "API key change build should be parked on the token fetch")

        // A foreground event delivered from the stopped observer's buffer starts its own build.
        let foregroundBuild = Task { await manager.handleAppLifecycleEvent(.foregrounded) }
        await settle()

        await gate.open()
        await foregroundBuild.value
        let secondInstalled = await waitUntil { self.activeViewModel?.apiKey == "second-key" }
        XCTAssertTrue(secondInstalled)
        await settle()

        lifecycleEvents.send(.backgrounded)
        let backgroundObserved = await waitUntil { self.lastBackgrounded != nil }
        XCTAssertTrue(backgroundObserved, "Lifecycle observation stopped after the superseded build")

        lifecycleEvents.send(.foregrounded)
        let foregroundObserved = await waitUntil { self.lastBackgrounded == nil }
        XCTAssertTrue(foregroundObserved, "Lifecycle observation stopped after the superseded build")
    }
}
