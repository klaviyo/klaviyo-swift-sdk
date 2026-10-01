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
    private nonisolated static let shortObservationWindow: TimeInterval = 1

    /// Longer than the handshake timeout (`NetworkSession.networkTimeout`), so a stale
    /// handshake timing out is also covered.
    private static let handshakeTimeoutObservationWindow: TimeInterval =
        .init(NetworkSession.networkTimeout) / 1_000_000_000 + 2

    /// Upper bound for waits on state that is expected to change.
    private nonisolated static let eventTimeout: TimeInterval = 10

    private let gate = BuildGate()
    private var defaultFetchInitialAuthToken: ((AuthTokenManager) async -> String?)?
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
        defaultFetchInitialAuthToken = manager.fetchInitialAuthToken
    }

    override func tearDown() async throws {
        await gate.releaseAll()
        if let defaultFetchInitialAuthToken {
            manager.fetchInitialAuthToken = defaultFetchInitialAuthToken
        }
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

    private var lifecycleObserver: LifecycleObserver? {
        Mirror(reflecting: manager).descendant("lifecycleObserver") as? LifecycleObserver
    }

    /// Polls `condition` until it holds or `timeout` elapses; returns its final value.
    private func waitUntil(
        timeout: TimeInterval = eventTimeout,
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await condition()
    }

    /// Registers a token provider, then makes every later webview build park on `gate`
    /// before fetching its token.
    private func gateTokenFetch() async throws {
        let providerCalls = InvocationCounter()
        let token = try makeTestJWT()
        await AuthTokenManager.shared.registerProvider {
            await providerCalls.increment()
            return token
        }
        await providerCalls.waitFor(atLeast: 1)

        let gate = gate
        let fetch = manager.fetchInitialAuthToken
        manager.fetchInitialAuthToken = { authTokenManager in
            await gate.park()
            return await fetch(authTokenManager)
        }
    }

    /// Waits until `count` builds have parked on the gated token fetch.
    private func waitForParkedBuilds(
        _ count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let gate = gate
        let parked = await waitUntil { await gate.arrivals >= count }
        XCTAssertTrue(parked, "Expected \(count) builds parked on the token fetch", file: file, line: line)
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
        try await gateTokenFetch()

        let build = startBuild(apiKey: "only-key")
        await waitForParkedBuilds(1)
        XCTAssertNil(manager.viewController, "Build should be parked on the token fetch")

        await gate.releaseAll()
        let installed = try await build.value

        XCTAssertTrue(installed)
        await assertActiveWebViewSurvives(apiKey: "only-key")
    }

    func testOverlappingBuildsInstallOnlyLatestAndKeepItAlive() async throws {
        try await gateTokenFetch()

        let first = startBuild(apiKey: "first-key")
        await waitForParkedBuilds(1)
        let second = startBuild(apiKey: "second-key")
        await waitForParkedBuilds(2)
        XCTAssertNil(manager.viewController, "Both builds should be parked on the token fetch")

        await gate.releaseNewest()
        let secondInstalled = try await second.value
        await gate.releaseAll()
        let firstInstalled = try await first.value

        XCTAssertTrue(secondInstalled)
        XCTAssertFalse(firstInstalled)
        await assertActiveWebViewSurvives(apiKey: "second-key")
    }

    func testAPIKeyChangeDuringGatedTokenFetchKeepsLatestWebViewAlive() async throws {
        try await gateTokenFetch()

        manager.initializeIAF(configuration: InAppFormsConfig())
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "first-key"))
        await waitForParkedBuilds(1)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "second-key"))
        await waitForParkedBuilds(2)
        XCTAssertNil(manager.viewController, "Both builds should be parked on the token fetch")

        await gate.releaseNewest()
        let secondInstalled = await waitUntil { self.activeViewModel?.apiKey == "second-key" }
        XCTAssertTrue(secondInstalled)
        await gate.releaseAll()
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
        try await gateTokenFetch()

        let build = startBuild(apiKey: "first-key")
        await waitForParkedBuilds(1)
        manager.destroyWebviewAndListeners()

        await gate.releaseAll()
        let installed = try await build.value
        await settle()

        XCTAssertFalse(installed)
        XCTAssertNil(manager.viewController)
        XCTAssertNil(activeViewModel)
    }

    func testRebuildAfterUnregisterDuringPendingBuildInstallsOnlyLatest() async throws {
        try await gateTokenFetch()

        let first = startBuild(apiKey: "first-key")
        await waitForParkedBuilds(1)
        manager.destroyWebviewAndListeners()
        let second = startBuild(apiKey: "second-key")
        await waitForParkedBuilds(2)
        XCTAssertNil(manager.viewController, "Both builds should be parked on the token fetch")

        await gate.releaseNewest()
        let secondInstalled = try await second.value
        await gate.releaseAll()
        let firstInstalled = try await first.value

        XCTAssertTrue(secondInstalled)
        XCTAssertFalse(firstInstalled)
        await assertActiveWebViewSurvives(apiKey: "second-key")
    }

    func testForegroundRebuildDuringAPIKeyChangeKeepsLifecycleObservationAlive() async throws {
        let lifecycleEvents = PassthroughSubject<LifeCycleEvents, Never>()
        environment.appLifeCycle = AppLifeCycleEvents(lifeCycleEvents: {
            lifecycleEvents.eraseToAnyPublisher()
        })

        manager.initializeIAF(configuration: InAppFormsConfig())
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "first-key"))
        let firstInstalled = await waitUntil {
            self.activeViewModel?.apiKey == "first-key" && self.lifecycleObserver != nil
        }
        XCTAssertTrue(firstInstalled)
        XCTAssertNil(lastBackgrounded)
        let firstObserver = lifecycleObserver

        try await gateTokenFetch()
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "second-key"))
        await waitForParkedBuilds(1)
        XCTAssertNil(manager.viewController, "API key change build should be parked on the token fetch")

        // A foreground event delivered from the stopped observer's buffer starts its own build.
        let foregroundBuild = Task { await manager.handleAppLifecycleEvent(.foregrounded) }
        await waitForParkedBuilds(2)

        await gate.releaseAll()
        await foregroundBuild.value
        let secondInstalled = await waitUntil { self.activeViewModel?.apiKey == "second-key" }
        XCTAssertTrue(secondInstalled)
        let observationRestarted = await waitUntil {
            self.lifecycleObserver != nil && self.lifecycleObserver !== firstObserver
        }
        XCTAssertTrue(observationRestarted, "Lifecycle observation not restarted after the API key change")
        await settle()

        // Lifecycle events are dispatched to the page via `evaluateJavaScript`, which
        // waits for the web content process; wait for it once before sending events.
        completeActiveHandshake()
        _ = try? await manager.viewController?.evaluateJavaScript("0")

        lifecycleEvents.send(.backgrounded)
        let backgroundObserved = await waitUntil { self.lastBackgrounded != nil }
        XCTAssertTrue(backgroundObserved, "Lifecycle observation stopped after the superseded build")

        lifecycleEvents.send(.foregrounded)
        let foregroundObserved = await waitUntil { self.lastBackgrounded == nil }
        XCTAssertTrue(foregroundObserved, "Lifecycle observation stopped after the superseded build")
    }
}

/// Holds webview builds at their token fetch until the test releases them.
private actor BuildGate {
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    /// Number of builds that have reached the gate.
    private(set) var arrivals = 0

    func park() async {
        arrivals += 1
        if isOpen { return }
        await withCheckedContinuation { parked.append($0) }
    }

    /// Resumes the most recently parked build.
    func releaseNewest() {
        parked.popLast()?.resume()
    }

    /// Resumes every parked build, newest first, and lets later builds pass.
    func releaseAll() {
        isOpen = true
        while let continuation = parked.popLast() {
            continuation.resume()
        }
    }
}
