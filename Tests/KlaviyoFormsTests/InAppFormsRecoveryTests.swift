@testable import KlaviyoCore
@testable import KlaviyoForms
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

    func testMissingResourceFailsAndDuplicateRegistrationKeepsOriginalHandler() async throws {
        var first = 0
        var duplicate = 0
        manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { first += 1 }))
        manager.initializeIAF(configuration: InAppFormsConfig(onFailure: { duplicate += 1 }))
        manager.indexHtmlFileUrl = nil
        let installed = try await manager.createFormWebViewAndListen(apiKey: "company")
        XCTAssertFalse(installed)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(duplicate, 0)
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
            onFailure: { XCTFail("ignored duplicate") }
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
}
