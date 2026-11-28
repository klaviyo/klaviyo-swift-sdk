@testable import KlaviyoCore
@testable import KlaviyoForms
import JavaScriptCore
import UIKit
import XCTest

@MainActor
final class IAFPresentationManagerManualFormTests: XCTestCase {
    private var manager: IAFPresentationManager!

    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        resetPresentationManagerStores()
        EventBus.shared.reset()
        manager = IAFPresentationManager(viewController: nil)
        manager.fetchInitialAuthToken = { _ in nil }
        manager.makeViewController = { ManualFormWebViewController(hosting: $0) }
        manager.indexHtmlFileUrl = Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html")
    }

    override func tearDown() async throws {
        manager.destroyWebviewAndListeners()
        manager = nil
        resetPresentationManagerStores()
        EventBus.shared.reset()
    }

    func testPublicCommandReturnsSDKForChainingWithoutRegistering() {
        struct HostSDK: KlaviyoSDKModule {}
        let chainedSDK = HostSDK().openForm("unregistered").openForm("also-unregistered")
        _ = chainedSDK
        XCTAssertNil(IAFPresentationManager.shared.viewModel)
    }

    func testHandshakeDoesNotDrainAndDataReadyDrainsLatestExactlyOnce() async throws {
        let page = try await install()
        manager.openForm("first")
        manager.dispatchFormEvent(.handShook, from: page.model)
        manager.openForm("latest")
        XCTAssertTrue(page.scripts.openScripts.isEmpty)
        manager.dispatchFormEvent(.formsDataLoaded, from: page.model)
        manager.dispatchFormEvent(.formsDataLoaded, from: page.model)
        await page.scripts.waitForScript(containing: "latest")
        XCTAssertEqual(try page.scripts.openedIDs(), ["latest"])
    }

    func testBridgeDataReadyReachesManagerWithoutPublicLifecycleCallback() async throws {
        let page = try await install()
        IAFPresentationManager.shared.registerFormLifecycleHandler { _ in XCTFail("Readiness is internal") }
        defer { IAFPresentationManager.shared.unregisterFormLifecycleHandler() }
        manager.openForm("bridged")
        page.model.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge", body: #"{"type":"formsDataLoaded","data":{}}"#
        ))
        await page.scripts.waitForScript(containing: "bridged")
        XCTAssertEqual(try page.scripts.openedIDs(), ["bridged"])
    }

    func testZeroWindowDropsLoadingButForwardsEveryReadyRequestWhileVisible() async throws {
        let page = try await install(window: 0)
        manager.openForm("loading")
        manager.dispatchFormEvent(.formsDataLoaded, from: page.model)
        page.visiblePresenter = UIViewController()
        manager.openForm("same")
        manager.openForm("same")
        manager.openForm("last")
        await page.scripts.waitForScript(containing: "last")
        XCTAssertEqual(try page.scripts.openedIDs(), ["same", "same", "last"])
    }

    func testDefaultAndCappedWindowsRetainLatestLoadingRequest() async throws {
        for window: TimeInterval? in [nil, 300] {
            let page = try await install(window: window)
            manager.openForm("pending")
            manager.dispatchFormEvent(.formsDataLoaded, from: page.model)
            await page.scripts.waitForScript(containing: "pending")
            XCTAssertEqual(try page.scripts.openedIDs(), ["pending"])
            manager.destroyWebviewAndListeners()
        }
    }

    func testConfigReplacementKeepsActiveWindowSnapshot() async throws {
        let page = try await install(window: 0)
        manager.initializeIAF(configuration: InAppFormsConfig(eventReplayWindow: 30))
        manager.openForm("must-drop")
        manager.dispatchFormEvent(.formsDataLoaded, from: page.model)
        manager.openForm("sentinel")
        await page.scripts.waitForScript(containing: "sentinel")
        XCTAssertEqual(try page.scripts.openedIDs(), ["sentinel"])
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "next-company"))
        await assertEventually { self.manager.viewModel?.apiKey == "next-company" }
        let next = try currentPage()
        XCTAssertFalse(next.model === page.model)
        XCTAssertEqual(next.model.apiKey, "next-company")
        manager.openForm("next-window")
        manager.dispatchFormEvent(.formsDataLoaded, from: next.model)
        await next.scripts.waitForScript(containing: "next-window")
        XCTAssertEqual(try next.scripts.openedIDs(), ["next-window"])
    }

    func testUnregisteredAndBlankRequestsCannotCreateOrReplacePendingWork() async throws {
        manager.openForm("unregistered")
        XCTAssertNil(manager.viewModel)
        let page = try await install()
        manager.openForm("valid")
        for blank in ["", " ", "\t\n\r"] {
            manager.openForm(blank)
        }
        manager.dispatchFormEvent(.formsDataLoaded, from: page.model)
        await page.scripts.waitForScript(containing: "valid")
        XCTAssertEqual(try page.scripts.openedIDs(), ["valid"])
    }

    func testInitialJWTWaitDoesNotQueueManualRequests() async throws {
        let arrived = Latch()
        let release = Latch()
        manager.fetchInitialAuthToken = { _ in
            await arrived.open()
            await release.wait()
            return nil
        }
        manager.initializeIAF(configuration: InAppFormsConfig(loadTimeout: 300))
        let build = Task { try await manager.createFormWebViewAndListen(apiKey: "company") }
        await arrived.wait()
        manager.openForm("before-runtime")
        XCTAssertNil(manager.viewModel)
        await release.open()
        _ = try await build.value
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "company"))
        let page = try currentPage()
        manager.dispatchFormEvent(.formsDataLoaded, from: page.model)
        manager.openForm("sentinel")
        await page.scripts.waitForScript(containing: "sentinel")
        XCTAssertEqual(try page.scripts.openedIDs(), ["sentinel"])
    }

    func testTeardownFailureAndAbortDiscardPendingAndOldReadiness() async throws {
        for operation in ["unregister", "failure", "abort", "rebuild"] {
            let retired = try await install()
            manager.openForm("retired-pending")
            switch operation {
            case "failure": manager.handleHandshakeFailure(for: retired.model)
            case "abort": manager.dispatchFormEvent(.abort, from: retired.model)
            case "rebuild": manager.tearDownFormWebView()
            default: manager.destroyWebviewAndListeners()
            }
            manager.openForm("without-runtime")
            XCTAssertNil(manager.viewModel)
            let next = try await install()
            manager.openForm("next-first")
            manager.dispatchFormEvent(.formsDataLoaded, from: retired.model)
            manager.openForm("next")
            XCTAssertTrue(next.scripts.openScripts.isEmpty)
            manager.dispatchFormEvent(.formsDataLoaded, from: next.model)
            await next.scripts.waitForScript(containing: "next")
            XCTAssertEqual(try retired.scripts.openedIDs(), [])
            XCTAssertEqual(try next.scripts.openedIDs(), ["next"])
            manager.destroyWebviewAndListeners()
        }
    }

    func testRebuildClearsReadinessAndKeepsOnlyLatestLoadingRequest() async throws {
        let first = try await install()
        manager.dispatchFormEvent(.formsDataLoaded, from: first.model)
        manager.tearDownFormWebView()
        let next = try await install()
        manager.openForm("loading-first")
        manager.openForm("latest")
        manager.dispatchFormEvent(.formsDataLoaded, from: next.model)
        await next.scripts.waitForScript(containing: "latest")
        XCTAssertEqual(try next.scripts.openedIDs(), ["latest"])
    }

    func testReplacementAndResetDiscardPendingButCompatibleEnrichmentPreservesIt() async throws {
        for replacement in [false, true] {
            IdentityStore.shared.update(ProfileData(email: "a@example.com", anonymousId: "anon"))
            let page = try await install()
            manager.openForm("retired-context")
            if replacement {
                IdentityStore.shared.update(ProfileData(email: "b@example.com", anonymousId: "anon"))
            } else {
                EventBus.shared.reset()
            }
            manager.dispatchFormEvent(.formsDataLoaded, from: page.model)
            manager.openForm("new-context")
            await page.scripts.waitForScript(containing: "new-context")
            XCTAssertEqual(try page.scripts.openedIDs(), ["new-context"])
            manager.destroyWebviewAndListeners()
        }
        IdentityStore.shared.update(ProfileData(anonymousId: "anon"))
        let page = try await install()
        manager.openForm("anonymous")
        IdentityStore.shared.update(ProfileData(email: "a@example.com", anonymousId: "anon"))
        manager.dispatchFormEvent(.formsDataLoaded, from: page.model)
        await page.scripts.waitForScript(containing: "anonymous")
        IdentityStore.shared.update(ProfileData(
            email: "a@example.com", externalId: "id", anonymousId: "anon"
        ))
        manager.openForm("enriched-ready")
        await page.scripts.waitForScript(containing: "enriched-ready")
        XCTAssertEqual(try page.scripts.openedIDs(), ["anonymous", "enriched-ready"])
    }

    func testScheduledCommandCannotReachReplacedPageOrCompanyOrIdentity() async throws {
        for change in ["page", "company", "identity", "reset"] {
            IdentityStore.shared.update(ProfileData(email: "a@example.com", anonymousId: "anon"))
            let retired = try await install()
            manager.dispatchFormEvent(.formsDataLoaded, from: retired.model)
            manager.openForm("scheduled")
            switch change {
            case "company": SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "other"))
            case "identity":
                IdentityStore.shared.update(ProfileData(email: "b@example.com", anonymousId: "anon"))
            case "reset": EventBus.shared.reset()
            default: manager.tearDownFormWebView()
            }
            if change == "page" || change == "company" {
                manager.tearDownFormWebView()
                let next = try await install()
                manager.dispatchFormEvent(.formsDataLoaded, from: next.model)
                manager.openForm("sentinel")
                await next.scripts.waitForScript(containing: "sentinel")
                XCTAssertEqual(try retired.scripts.openedIDs(), [])
                XCTAssertEqual(try next.scripts.openedIDs(), ["sentinel"])
            } else {
                manager.openForm("sentinel")
                await retired.scripts.waitForScript(containing: "sentinel")
                XCTAssertEqual(try retired.scripts.openedIDs(), ["sentinel"])
            }
            manager.destroyWebviewAndListeners()
        }
    }

    private func install(window: TimeInterval? = nil) async throws -> ManualFormWebViewController {
        SDKConfigStore.shared.reset()
        manager.initializeIAF(configuration: InAppFormsConfig(
            loadTimeout: 300, eventReplayWindow: window ?? 10
        ))
        try await manager.createFormWebViewAndListen(apiKey: "company")
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "company"))
        return try currentPage()
    }

    private func currentPage() throws -> ManualFormWebViewController {
        try XCTUnwrap(manager.viewController as? ManualFormWebViewController)
    }
}

@MainActor
private final class ManualFormWebViewController: KlaviyoWebViewController {
    let model: IAFWebViewModel
    let scripts: MockIAFWebViewDelegate
    var visiblePresenter: UIViewController?

    override var presentingViewController: UIViewController? {
        visiblePresenter
    }

    init(hosting model: IAFWebViewModel) {
        self.model = model
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

@MainActor
extension MockIAFWebViewDelegate {
    fileprivate var openScripts: [String] {
        evaluatedScripts.filter { $0.hasPrefix("window.openForm(") }
    }

    fileprivate func openedIDs() throws -> [String] {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var opened = [];
        var window = { openForm: function(id) { opened.push(id); } };
        """)
        openScripts.forEach { context.evaluateScript($0) }
        XCTAssertNil(context.exception)
        return try XCTUnwrap(context.evaluateScript("opened")?.toArray() as? [String])
    }
}
