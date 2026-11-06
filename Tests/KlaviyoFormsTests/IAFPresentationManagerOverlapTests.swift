//
//  IAFPresentationManagerOverlapTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import Combine
import KlaviyoCore
import XCTest

/// Covers `createFormWebViewAndListen` builds that overlap across the auth-token fetch,
/// events and handshake failures from a replaced webview, and unregistering mid-build.
@MainActor
final class IAFPresentationManagerOverlapTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        registerWithUIKitServicesOnMain()
    }

    /// Handshake timeout for every build, longer than any test, so no handshake times out.
    private static let activeHandshakeTimeout: TimeInterval = 300

    private let gate = BuildGate()
    private var defaultFetchInitialAuthToken: ((AuthTokenManager) async -> AuthTokenManager.TokenRefresh?)?
    private var defaultMakeViewController: ((IAFWebViewModel) -> KlaviyoWebViewController)?
    private var defaultHandshakeTimeout: TimeInterval?
    private var manager: IAFPresentationManager {
        .shared
    }

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        resetPresentationManagerStores()
        IdentityStore.shared.update(ProfileData(email: "user@example.com"))
        await AuthTokenManager.shared.unregisterProvider()
        await resetManager()
        defaultFetchInitialAuthToken = manager.fetchInitialAuthToken
        defaultMakeViewController = manager.makeViewController
        defaultHandshakeTimeout = manager.handshakeTimeout
        manager.handshakeTimeout = Self.activeHandshakeTimeout
        manager.makeViewController = { InertWebViewController(hosting: $0) }
    }

    override func tearDown() async throws {
        await gate.releaseAll()
        if let defaultFetchInitialAuthToken {
            manager.fetchInitialAuthToken = defaultFetchInitialAuthToken
        }
        if let defaultMakeViewController {
            manager.makeViewController = defaultMakeViewController
        }
        if let defaultHandshakeTimeout {
            manager.handshakeTimeout = defaultHandshakeTimeout
        }
        await AuthTokenManager.shared.unregisterProvider()
        await resetManager()
        resetPresentationManagerStores()
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Unregisters the shared manager and clears the background timestamp a previous
    /// `.backgrounded` event left behind. With no webview, the foreground event only
    /// consumes that timestamp.
    private func resetManager() async {
        manager.destroyWebviewAndListeners()
        if lastBackgrounded != nil {
            await manager.handleAppLifecycleEvent(.foregrounded)
        }
    }

    private var activeViewModel: IAFWebViewModel? {
        manager.viewModel
    }

    private var lastBackgrounded: Date? {
        Mirror(reflecting: manager).descendant("lastBackgrounded") as? Date
    }

    private var lifecycleObserver: LifecycleObserver? {
        Mirror(reflecting: manager).descendant("lifecycleObserver") as? LifecycleObserver
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

    /// Suspends until `count` builds have reached the gated token fetch, failing the test
    /// when they do not within ``hangSafeguard``.
    private func waitForParkedBuilds(
        _ count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let gate = gate
        try await awaitBounded("\(count) parked builds", file: file, line: line) {
            await gate.waitForArrivals(count)
        }
    }

    private func startBuild(apiKey: String) -> Task<Bool, Error> {
        Task { try await manager.createFormWebViewAndListen(apiKey: apiKey) }
    }

    // MARK: - Tests

    func testFormEventFromReplacedWebViewDoesNotTearDownActiveWebView() async throws {
        try await gateTokenFetch()
        let first = startBuild(apiKey: "first-key")
        try await waitForParkedBuilds(1)
        await gate.releaseAll()
        let firstInstalled = try await first.value
        let replaced = try XCTUnwrap(activeViewModel)

        let second = startBuild(apiKey: "second-key")
        try await waitForParkedBuilds(2)
        await gate.releaseAll()
        let secondInstalled = try await second.value
        let active = try XCTUnwrap(activeViewModel)
        XCTAssertTrue(firstInstalled)
        XCTAssertTrue(secondInstalled)

        manager.dispatchFormEvent(.abort, from: replaced)
        XCTAssertNotNil(manager.viewController, "A replaced webview's abort must not tear down the active one")
        XCTAssertEqual(activeViewModel?.apiKey, "second-key")

        manager.dispatchFormEvent(.abort, from: active)
        XCTAssertNil(manager.viewController, "The active webview's own abort still tears it down")
    }

    func testOverlappingBuildsInstallOnlyLatestAndKeepItAlive() async throws {
        try await gateTokenFetch()

        let first = startBuild(apiKey: "first-key")
        try await waitForParkedBuilds(1)
        let second = startBuild(apiKey: "second-key")
        try await waitForParkedBuilds(2)
        XCTAssertNil(manager.viewController, "Both builds should be parked on the token fetch")

        await gate.releaseNewest()
        let secondInstalled = try await second.value
        await gate.releaseAll()
        let firstInstalled = try await first.value

        XCTAssertTrue(secondInstalled)
        XCTAssertFalse(firstInstalled)
        XCTAssertNotNil(manager.viewController, "The superseded build must not tear down the latest one")
        XCTAssertEqual(activeViewModel?.apiKey, "second-key")
    }

    func testUnregisterDuringPendingBuildPreventsInstall() async throws {
        try await gateTokenFetch()

        let build = startBuild(apiKey: "first-key")
        try await waitForParkedBuilds(1)
        manager.destroyWebviewAndListeners()

        await gate.releaseAll()
        let installed = try await build.value

        XCTAssertFalse(installed)
        XCTAssertNil(manager.viewController)
        XCTAssertNil(activeViewModel)
    }

    func testHandshakeFailureFromReplacedWebViewDoesNotTearDownActiveWebView() async throws {
        try await manager.createFormWebViewAndListen(apiKey: "first-key")
        let replaced = try XCTUnwrap(activeViewModel)
        manager.tearDownFormWebView()
        try await manager.createFormWebViewAndListen(apiKey: "second-key")
        let active = try XCTUnwrap(activeViewModel)

        manager.handleHandshakeFailure(for: replaced)
        XCTAssertNotNil(
            manager.viewController,
            "A replaced webview's handshake failure must not tear down the active one"
        )
        XCTAssertEqual(activeViewModel?.apiKey, "second-key")

        manager.handleHandshakeFailure(for: active)
        XCTAssertNil(manager.viewController, "The active webview's own handshake failure still tears it down")
    }

    // MARK: Registration state stream

    /// Reads the first `count` values from `states`. The stream subscribes when it is created and
    /// buffers, so values sent before reading are not lost.
    private func first(_ count: Int, of states: AsyncStream<Bool>) async -> [Bool] {
        var iterator = states.makeAsyncIterator()
        var values: [Bool] = []
        while values.count < count, let value = await iterator.next() {
            values.append(value)
        }
        return values
    }

    func testRegistrationStatesStartWithCurrentState() async {
        let states = await first(1, of: manager.registrationStates())
        XCTAssertEqual(states, [false])
    }

    func testRegistrationStatesReportRegisterAndUnregister() async {
        let states = manager.registrationStates()

        manager.initializeIAF(configuration: InAppFormsConfig())
        manager.initializeIAF(configuration: InAppFormsConfig())
        manager.destroyWebviewAndListeners()
        manager.destroyWebviewAndListeners()
        manager.initializeIAF(configuration: InAppFormsConfig())

        let values = await first(4, of: states)
        XCTAssertEqual(values, [false, true, false, true], "Calls that don't change state are not reported")
    }

    func testRegistrationStatesReportSelfTeardownOnHandshakeFailure() async throws {
        manager.initializeIAF(configuration: InAppFormsConfig())
        try await manager.createFormWebViewAndListen(apiKey: "key")
        let active = try XCTUnwrap(activeViewModel)
        let states = manager.registrationStates()

        manager.handleHandshakeFailure(for: active)

        let values = await first(2, of: states)
        XCTAssertEqual(values, [true, false])
    }

    func testRegistrationStatesReportSelfTeardownOnAbort() async throws {
        manager.initializeIAF(configuration: InAppFormsConfig())
        try await manager.createFormWebViewAndListen(apiKey: "key")
        let active = try XCTUnwrap(activeViewModel)
        let states = manager.registrationStates()

        manager.dispatchFormEvent(.abort, from: active)

        let values = await first(2, of: states)
        XCTAssertEqual(values, [true, false])
    }

    func testRegistrationStatesSupportMultipleSubscribers() async {
        let firstStates = manager.registrationStates()
        let secondStates = manager.registrationStates()

        manager.initializeIAF(configuration: InAppFormsConfig())

        let firstValues = await first(2, of: firstStates)
        let secondValues = await first(2, of: secondStates)
        XCTAssertEqual(firstValues, [false, true])
        XCTAssertEqual(secondValues, [false, true])
    }

    func testCancellingRegistrationStatesIterationEndsTheStream() async {
        let states = manager.registrationStates()
        let iteration = Task {
            for await _ in states {}
        }

        iteration.cancel()

        // Finishes only because cancellation terminates the stream.
        await iteration.value
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
        try await waitForParkedBuilds(1)
        XCTAssertNil(manager.viewController, "API key change build should be parked on the token fetch")

        // A foreground event delivered from the stopped observer's buffer starts its own build.
        let foregroundBuild = Task { await manager.handleAppLifecycleEvent(.foregrounded) }
        try await waitForParkedBuilds(2)

        await gate.releaseAll()
        await foregroundBuild.value
        let secondInstalled = await waitUntil { self.activeViewModel?.apiKey == "second-key" }
        XCTAssertTrue(secondInstalled)
        let observationRestarted = await waitUntil {
            self.lifecycleObserver != nil && self.lifecycleObserver !== firstObserver
        }
        XCTAssertTrue(observationRestarted, "Lifecycle observation not restarted after the API key change")

        lifecycleEvents.send(.backgrounded)
        let backgroundObserved = await waitUntil { self.lastBackgrounded != nil }
        XCTAssertTrue(backgroundObserved, "Lifecycle observation stopped after the superseded build")
    }
}

/// Holds webview builds at their token fetch until the test releases them.
private actor BuildGate {
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    private var arrivals = 0
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func park() async {
        arrivals += 1
        arrivalWaiters.removeAll { waiter in
            guard arrivals >= waiter.count else { return false }
            waiter.continuation.resume()
            return true
        }
        if isOpen { return }
        await withCheckedContinuation { parked.append($0) }
    }

    /// Suspends until `count` builds have reached the gate.
    func waitForArrivals(_ count: Int) async {
        if arrivals >= count { return }
        await withCheckedContinuation { arrivalWaiters.append((count, $0)) }
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
