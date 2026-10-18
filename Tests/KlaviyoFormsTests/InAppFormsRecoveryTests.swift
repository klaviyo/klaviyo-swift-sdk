@testable import KlaviyoCore
@testable import KlaviyoForms
import WebKit
import XCTest

@MainActor
final class InAppFormsRecoveryTests: XCTestCase {
    private var manager: IAFPresentationManager!

    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        resetPresentationManagerStores()
        manager = IAFPresentationManager(viewController: nil)
        manager.fetchInitialAuthToken = { _ in nil }
        manager.makeViewController = { InertWebViewController(hosting: $0) }
        manager.indexHtmlFileUrl = Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html")
    }

    override func tearDown() async throws {
        manager.destroyWebviewAndListeners()
        manager = nil
        resetPresentationManagerStores()
    }

    func testConfigurationNormalizesTimeoutAndReplayWithoutChangingSession() {
        for invalid in [0, -1, .infinity, -.infinity, .nan, .greatestFiniteMagnitude] as [TimeInterval] {
            XCTAssertNil(InAppFormsConfig(loadTimeout: invalid).loadTimeout)
        }
        XCTAssertEqual(InAppFormsConfig(loadTimeout: 2.5).loadTimeout, 2.5)
        XCTAssertNil(InAppFormsConfig().loadTimeout)
        for (input, expected) in [(-1.0, 0.0), (-.infinity, 0), (.infinity, 30), (31, 30), (.nan, 10)] {
            XCTAssertEqual(InAppFormsConfig(eventReplayWindow: input).eventReplayWindow, expected)
        }
        XCTAssertEqual(InAppFormsConfig(sessionTimeoutDuration: .infinity).sessionTimeoutDuration, .infinity)
    }

    func testFailureTearsDownBeforeCallbackAndAllowsImmediateRegistration() async throws {
        var failures = 0
        manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { [self] in
            failures += 1
            XCTAssertNil(manager.viewModel)
            XCTAssertNil(manager.viewController)
            manager.initializeIAF(configuration: InAppFormsConfig(eventReplayWindow: 0))
        }))
        try await manager.createFormWebViewAndListen(apiKey: "company")
        let failed = try XCTUnwrap(manager.viewModel)
        manager.handleHandshakeFailure(for: failed)
        manager.handleHandshakeFailure(for: failed)
        XCTAssertEqual(failures, 1)
        try await manager.createFormWebViewAndListen(apiKey: "company")
        XCTAssertNotNil(manager.viewModel)
    }

    func testRegistrationBeforeBuildUsesLatestFailureHandler() async throws {
        var first = 0
        var duplicate = 0
        manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { first += 1 }))
        manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { duplicate += 1 }))
        manager.indexHtmlFileUrl = nil
        let installed = try await manager.createFormWebViewAndListen(apiKey: "company")
        XCTAssertFalse(installed)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(duplicate, 1)
        XCTAssertNil(manager.viewModel)
    }

    func testAbortBeforeHandshakeFailsButAfterHandshakeIsSilent() async throws {
        var failures = 0
        manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { failures += 1 }))
        try await manager.createFormWebViewAndListen(apiKey: "company")
        manager.handleFormEvent(.abort)
        XCTAssertEqual(failures, 1)
        manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { failures += 1 }))
        try await manager.createFormWebViewAndListen(apiKey: "company")
        manager.handleFormEvent(.handShook)
        manager.handleFormEvent(.abort)
        XCTAssertEqual(failures, 1)
    }

    func testUnregisterAndObsoleteFailureAreSilent() async throws {
        var failures = 0
        manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { failures += 1 }))
        try await manager.createFormWebViewAndListen(apiKey: "company")
        let obsolete = try XCTUnwrap(manager.viewModel)
        manager.destroyWebviewAndListeners()
        manager.handleHandshakeFailure(for: obsolete)
        XCTAssertEqual(failures, 0)
    }

    func testMainDocumentAndRendererFailuresSettleOnce() async throws {
        for navigation in [
            WKNavigationEvent.didFailProvisionalNavigation,
            .didFailNavigation,
            .webContentProcessTerminated
        ] {
            var failures = 0
            manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { failures += 1 }))
            try await manager.createFormWebViewAndListen(apiKey: "company")
            let model = try XCTUnwrap(manager.viewModel)
            model.handleNavigationEvent(navigation)
            model.handleNavigationEvent(navigation)
            XCTAssertEqual(failures, 1)
            XCTAssertNil(model.delegate)
            XCTAssertNil(manager.viewModel)
        }
    }

    func testBridgeAbortBeforeHandshakeSettlesSynchronously() async throws {
        var failures = 0
        manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { failures += 1 }))
        try await manager.createFormWebViewAndListen(apiKey: "company")
        let model = try XCTUnwrap(manager.viewModel)
        model.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge", body: #"{"type":"abort","data":{"reason":"failed"}}"#
        ))
        model.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge", body: #"{"type":"handShook","data":{}}"#
        ))
        XCTAssertEqual(failures, 1)
        XCTAssertNil(manager.viewController)
        XCTAssertFalse(model.hasCompletedHandshake)
    }

    func testTimeoutStartsAfterJWTWaitAndKeepsAcceptedConfiguration() async throws {
        let arrived = Latch()
        let release = Latch()
        var failures = 0
        manager.fetchInitialAuthToken = { _ in
            await arrived.open()
            await release.wait()
            return nil
        }
        manager.initializeIAF(configuration: InAppFormsConfig(
            loadTimeout: 0.01,
            onFailure: { failures += 1 }
        ))
        let build = Task { try await manager.createFormWebViewAndListen(apiKey: "company") }
        await arrived.wait()
        manager.initializeIAF(configuration: InAppFormsConfig(
            loadTimeout: 300,
            onFailure: { XCTFail("Future handler ran for the active attempt") }
        ))
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(failures, 0)
        XCTAssertNil(manager.viewModel)
        await release.open()
        _ = try await build.value
        let failed = await waitUntil { failures == 1 }
        XCTAssertTrue(failed)
    }

    func testAcceptedHandlerAppliesToARebuildAfterSuccessfulHandshake() async throws {
        var failures = 0
        manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { failures += 1 }))
        try await manager.createFormWebViewAndListen(apiKey: "company")
        manager.handleFormEvent(.handShook)
        manager.tearDownFormWebView()
        manager.indexHtmlFileUrl = nil
        let installed = try await manager.createFormWebViewAndListen(apiKey: "company")
        XCTAssertFalse(installed)
        XCTAssertEqual(failures, 1)
    }

    func testUnregisterReleasesHandlerWhileJWTBuildIsStillWaiting() async throws {
        let arrived = Latch()
        let release = Latch()
        manager.fetchInitialAuthToken = { _ in
            await arrived.open()
            await release.wait()
            return nil
        }
        weak var retained: NSObject?
        do {
            let marker = NSObject()
            retained = marker
            manager.initializeIAF(configuration: InAppFormsConfig(onFailure: {
                XCTFail("Unregister unexpectedly failed: \(marker)")
            }))
        }
        let build = Task { try await manager.createFormWebViewAndListen(apiKey: "company") }
        await arrived.wait()
        manager.destroyWebviewAndListeners()
        XCTAssertNil(retained)
        await release.open()
        let installed = try await build.value
        XCTAssertFalse(installed)
    }

    func testCancelledForegroundCompletionCannotSupersedeJWTWaitingRetry() async throws {
        try await assertForegroundCannotSupersedeRetry(cancelForeground: true, failJavaScript: false)
    }

    func testCancelledForegroundErrorCannotSupersedeJWTWaitingRetry() async throws {
        try await assertForegroundCannotSupersedeRetry(cancelForeground: true, failJavaScript: true)
    }

    func testReplacedForegroundCompletionCannotSupersedeJWTWaitingRetry() async throws {
        try await assertForegroundCannotSupersedeRetry(cancelForeground: false, failJavaScript: false)
    }

    func testAlreadyCancelledBuildLeavesJWTWaitingRetryIntact() async throws {
        let arrived = Latch()
        let release = Latch()
        var fetches = 0
        var failures = 0
        manager.initializeIAF(configuration: InAppFormsConfig(loadTimeout: 300, onFailure: { failures += 1 }))
        manager.fetchInitialAuthToken = { _ in
            fetches += 1
            if fetches == 1 {
                await arrived.open()
                await release.wait()
            }
            return nil
        }
        let retry = Task { try await manager.createFormWebViewAndListen(apiKey: "company") }
        await arrived.wait()
        let cancelled = Task { try await manager.createFormWebViewAndListen(apiKey: "company") }
        cancelled.cancel()
        let cancelledInstalled = try await cancelled.value
        XCTAssertFalse(cancelledInstalled)
        XCTAssertEqual(fetches, 1)
        await release.open()
        let installed = try await retry.value
        XCTAssertTrue(installed)
        try manager.handleHandshakeFailure(for: XCTUnwrap(manager.viewModel))
        XCTAssertEqual(failures, 1)
    }
}

extension InAppFormsRecoveryTests {
    func testDuplicateDuringJWTWaitKeepsActiveHandlerAndAssetSnapshot() async throws {
        let arrived = Latch()
        let release = Latch()
        var fetches = 0
        var firstFailures = 0
        var futureFailures = 0
        manager.fetchInitialAuthToken = { _ in
            fetches += 1
            await arrived.open()
            await release.wait()
            return nil
        }
        manager.initializeIAF(
            configuration: InAppFormsConfig(loadTimeout: 300, onFailure: { firstFailures += 1 }),
            assetSource: "first-assets"
        )
        let build = Task { try await manager.createFormWebViewAndListen(apiKey: "company") }
        await arrived.wait()
        manager.initializeIAF(
            configuration: InAppFormsConfig(loadTimeout: 300, onFailure: { futureFailures += 1 }),
            assetSource: "future-assets"
        )
        XCTAssertEqual(fetches, 1)
        await release.open()
        let installed = try await build.value
        XCTAssertTrue(installed)
        let model = try XCTUnwrap(manager.viewModel)
        let sources = model.loadScripts?.map(\.source) ?? []
        XCTAssertTrue(sources.contains { $0.contains("assetSource=first-assets") })
        XCTAssertFalse(sources.contains { $0.contains("assetSource=future-assets") })
        manager.handleHandshakeFailure(for: model)
        XCTAssertEqual(firstFailures, 1)
        XCTAssertEqual(futureFailures, 0)
    }

    func testDuplicateAfterHandshakeUpdatesNextAttemptWithoutReplacingActivePage() async throws {
        var fetches = 0
        var firstFailures = 0
        var futureFailures = 0
        manager.fetchInitialAuthToken = { _ in fetches += 1; return nil }
        manager.initializeIAF(
            configuration: InAppFormsConfig(loadTimeout: 300, onFailure: { firstFailures += 1 }),
            assetSource: "first-assets"
        )
        try await manager.createFormWebViewAndListen(apiKey: "company")
        let active = try XCTUnwrap(manager.viewModel)
        active.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge", body: #"{"type":"handShook","data":{}}"#
        ))
        manager.initializeIAF(
            configuration: InAppFormsConfig(loadTimeout: 300, onFailure: { futureFailures += 1 }),
            assetSource: "future-assets"
        )
        XCTAssertTrue(manager.viewModel === active)
        XCTAssertEqual(fetches, 1)

        manager.tearDownFormWebView()
        try await manager.createFormWebViewAndListen(apiKey: "company")
        let next = try XCTUnwrap(manager.viewModel)
        XCTAssertFalse(next === active)
        XCTAssertEqual(fetches, 2)
        let sources = next.loadScripts?.map(\.source) ?? []
        XCTAssertTrue(sources.contains { $0.contains("assetSource=future-assets") })
        manager.handleHandshakeFailure(for: next)
        XCTAssertEqual(firstFailures, 0)
        XCTAssertEqual(futureFailures, 1)
    }

    func testDuplicateReplayWindowAppliesToNextAttemptAndKeepsCurrentReplaySnapshot() async throws {
        EventBus.shared.reset()
        defer { EventBus.shared.reset() }
        manager.makeViewController = { HeldLifecycleWebViewController(hosting: $0) }
        EventBus.shared.publish(Event(name: .customEvent("before-register")))
        manager.initializeIAF(configuration: InAppFormsConfig(loadTimeout: 300, eventReplayWindow: 0))
        try await manager.createFormWebViewAndListen(apiKey: "company")
        let active = try XCTUnwrap(manager.viewController as? HeldLifecycleWebViewController)
        manager.initializeIAF(configuration: InAppFormsConfig(loadTimeout: 300, eventReplayWindow: 30))
        manager.handleFormEvent(.handShook)
        EventBus.shared.publish(Event(name: .customEvent("after-register")))
        await active.scripts.waitForScript(containing: "after-register")
        let activeEvents = active.scripts.evaluatedScripts.filter { $0.hasPrefix("dispatchProfileEvent(") }
        XCTAssertEqual(activeEvents.count, 1)
        XCTAssertTrue(activeEvents.first?.contains("after-register") == true)

        manager.tearDownFormWebView()
        try await manager.createFormWebViewAndListen(apiKey: "company")
        let next = try XCTUnwrap(manager.viewController as? HeldLifecycleWebViewController)
        manager.handleFormEvent(.handShook)
        await next.scripts.waitForScript(containing: "after-register")
        let nextEvents = next.scripts.evaluatedScripts.filter { $0.hasPrefix("dispatchProfileEvent(") }
        XCTAssertEqual(nextEvents.count, 2)
        XCTAssertTrue(nextEvents.first?.contains("before-register") == true)
        XCTAssertTrue(nextEvents.last?.contains("after-register") == true)
    }

    private func assertForegroundCannotSupersedeRetry(
        cancelForeground: Bool,
        failJavaScript: Bool
    ) async throws {
        var oldFailures = 0
        var retryFailures = 0
        manager.makeViewController = { HeldLifecycleWebViewController(hosting: $0) }
        manager.initializeIAF(configuration: InAppFormsConfig(
            loadTimeout: 300,
            onFailure: { oldFailures += 1 }
        ))
        try await manager.createFormWebViewAndListen(apiKey: "company")
        let oldController = try XCTUnwrap(manager.viewController as? HeldLifecycleWebViewController)
        let oldModel = try XCTUnwrap(manager.viewModel)
        oldModel.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge", body: #"{"type":"handShook","data":{}}"#
        ))
        let script = "dispatchLifecycleEvent('foreground')"
        let hold = oldController.scripts.holdScript(containing: script)
        if failJavaScript { oldController.scripts.failScript(containing: script) }
        let foreground = Task { await manager.handleAppLifecycleEvent(.foregrounded) }
        try await awaitBounded("foreground JavaScript suspended") { await hold.reached.wait() }

        manager.destroyWebviewAndListeners()
        if cancelForeground { foreground.cancel() }
        manager.initializeIAF(configuration: InAppFormsConfig(
            loadTimeout: 0.01, eventReplayWindow: 0, onFailure: { retryFailures += 1 }
        ))
        let arrived = Latch()
        let release = Latch()
        var fetches = 0
        manager.fetchInitialAuthToken = { _ in
            fetches += 1
            if fetches == 1 {
                await arrived.open()
                await release.wait()
            }
            return nil
        }
        let retry = Task { try await manager.createFormWebViewAndListen(apiKey: "company") }
        try await awaitBounded("retry JWT suspended") { await arrived.wait() }
        await hold.release.open()
        try await awaitBounded("obsolete foreground completed") { await foreground.value }
        XCTAssertEqual(fetches, 1)
        await release.open()
        let installed = try await retry.value
        XCTAssertTrue(installed)
        XCTAssertNotNil(manager.viewModel)
        let notified = await waitUntil(timeout: 1) { retryFailures == 1 }
        XCTAssertTrue(notified, "Retry must retain its accepted timeout and failure handler")
        XCTAssertEqual(oldFailures, 0)
        XCTAssertNil(manager.viewController)
    }
}

@MainActor
private final class HeldLifecycleWebViewController: KlaviyoWebViewController {
    let scripts: MockIAFWebViewDelegate

    init(hosting model: IAFWebViewModel) {
        scripts = MockIAFWebViewDelegate(viewModel: model)
        super.init(viewModel: model, webViewFactory: { InertWebView() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func evaluateJavaScript(_ script: String) async throws -> Any? {
        try await scripts.evaluateJavaScript(script)
    }
}
