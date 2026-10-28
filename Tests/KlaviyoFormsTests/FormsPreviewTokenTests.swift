//
//  FormsPreviewTokenTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
import KlaviyoCore
import WebKit
import XCTest

let validPreviewToken = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJ0123-_6"

@MainActor
final class FormsPreviewTokenWebViewModelTests: XCTestCase {
    private var store: FormsPreviewTokenStore!

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        environment.cdnURL = {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "static.klaviyo.com"
            return components
        }
        store = FormsPreviewTokenStore()
    }

    private func makeViewModel() throws -> (IAFWebViewModel, MockIAFWebViewDelegate) {
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let viewModel = IAFWebViewModel(
            url: fileUrl,
            apiKey: "abc123",
            profileData: nil,
            previewTokenStore: store
        )
        let delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
        return (viewModel, delegate)
    }

    private func previewTokenLoadScript(in viewModel: IAFWebViewModel) -> WKUserScript? {
        viewModel.loadScripts?.first { $0.source.contains("data-klaviyo-forms-preview-token") }
    }

    func testNoPreviewTokenScriptWithoutToken() throws {
        let (viewModel, _) = try makeViewModel()
        XCTAssertNil(previewTokenLoadScript(in: viewModel))
    }

    func testLoadScriptSeedsStoredToken() throws {
        store.setToken(validPreviewToken)
        let (viewModel, _) = try makeViewModel()
        let script = try XCTUnwrap(previewTokenLoadScript(in: viewModel))
        XCTAssertTrue(script.source.contains(validPreviewToken))
    }

    func testPreviewEndedClearsStoredTokenAndLeavesThePageAlone() throws {
        store.setToken(validPreviewToken)
        let (viewModel, delegate) = try makeViewModel()
        viewModel.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: #"{"type":"formsPreviewEnded","data":{"reason":"expired"}}"#
        ))
        XCTAssertNil(store.token)
        XCTAssertTrue(delegate.evaluatedScripts.isEmpty, "The page is not written to")
    }
}

/// Starting or ending a forms preview restarts a registered session, like unregistering and
/// registering again; onsite-in-app-forms only reads the token when KlaviyoJS loads.
@MainActor
final class FormsPreviewSessionTests: XCTestCase {
    private var store: FormsPreviewTokenStore!
    private var manager: IAFPresentationManager!

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        resetPresentationManagerStores()
        store = FormsPreviewTokenStore()
        manager = IAFPresentationManager(viewController: nil)
        manager.indexHtmlFileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        manager.makeViewController = { InertWebViewController(hosting: $0) }
        manager.fetchInitialAuthToken = { _ in nil }
        // The inert webview never completes the handshake; keep its timeout out of the test
        manager.handshakeTimeout = 300
        manager.previewTokenStore = try XCTUnwrap(store)
    }

    override func tearDown() async throws {
        store.restartFormsSession = nil
        // Let a pending restart finish so no build outlives this test
        await manager.sessionRestartTask?.value
        manager.destroyWebviewAndListeners()
        resetPresentationManagerStores()
        manager = nil
        store = nil
        try await super.tearDown()
    }

    /// Builds the first webview and wires the store's restart hook to this manager, as
    /// `initializeIAF` does, without starting its app-wide company and lifecycle observers.
    private func register() async throws -> IAFWebViewModel {
        try await manager.createFormWebViewAndListen(apiKey: "abc123")
        store.restartFormsSession = { [weak manager] in manager?.restartFormsSession() }
        return try XCTUnwrap(manager.viewModel)
    }

    /// Unhooks the store and tears down the webview and its listeners, as unregistering does.
    private func unregister() {
        store.restartFormsSession = nil
        manager.tearDownFormWebView()
    }

    /// Waits for a restart to replace `previous`. The restart clears the view model before it
    /// builds the next one, so a `nil` view model doesn't count.
    private func restartedViewModel(replacing previous: IAFWebViewModel) async throws -> IAFWebViewModel {
        await manager.sessionRestartTask?.value
        await assertEventually { self.manager.viewModel.map { $0 !== previous } ?? false }
        return try XCTUnwrap(manager.viewModel)
    }

    func testPreviewStartedBeforeRegisterIsLoadedByTheFirstSession() async throws {
        store.startPreview(validPreviewToken)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(manager.viewModel, "No forms before the app registers")

        let first = try await register()

        XCTAssertEqual(first.previewToken, validPreviewToken)
    }

    func testStartingAPreviewRestartsTheSession() async throws {
        let first = try await register()
        XCTAssertNil(first.previewToken)

        store.startPreview(validPreviewToken)

        let restarted = try await restartedViewModel(replacing: first)
        XCTAssertEqual(restarted.previewToken, validPreviewToken)
    }

    func testStartingTheSamePreviewAgainRestartsTheSession() async throws {
        store.startPreview(validPreviewToken)
        let first = try await register()

        store.startPreview(validPreviewToken)

        let restarted = try await restartedViewModel(replacing: first)
        XCTAssertEqual(restarted.previewToken, validPreviewToken)
    }

    func testEndingAPreviewRestartsWithPublishedForms() async throws {
        store.startPreview(validPreviewToken)
        let first = try await register()

        store.endPreview()

        let restarted = try await restartedViewModel(replacing: first)
        XCTAssertNil(restarted.previewToken)
    }

    func testMalformedTokenChangesNothing() async throws {
        store.startPreview(validPreviewToken)
        let first = try await register()

        XCTAssertFalse(store.startPreview("not-a-preview-token"))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.token, validPreviewToken)
        XCTAssertTrue(manager.viewModel === first)
    }

    func testPreviewEndedClearsTheTokenWithoutRestarting() async throws {
        store.startPreview(validPreviewToken)
        let viewModel = try await register()

        viewModel.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: #"{"type":"formsPreviewEnded","data":{"reason":"expired"}}"#
        ))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(store.token)
        XCTAssertTrue(manager.viewModel === viewModel)
    }

    func testAfterUnregisterAPreviewWaitsForRegister() async throws {
        _ = try await register()
        unregister()

        store.startPreview(validPreviewToken)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(manager.viewModel)
        XCTAssertEqual(store.token, validPreviewToken)
    }
}

/// Exercises the public methods against the shared store. No forms session is registered, so
/// nothing restarts the shared presentation manager, which other suites use.
@MainActor
final class FormsPreviewTokenPublicAPITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        FormsPreviewTokenStore.shared.restartFormsSession = nil
        FormsPreviewTokenStore.shared.clear()
    }

    override func tearDown() async throws {
        FormsPreviewTokenStore.shared.clear()
        try await super.tearDown()
    }

    func testStartAndEndPreview() {
        KlaviyoSDK().startFormsPreview(validPreviewToken)
        XCTAssertEqual(FormsPreviewTokenStore.shared.token, validPreviewToken)
        KlaviyoSDK().endFormsPreview()
        XCTAssertNil(FormsPreviewTokenStore.shared.token)
    }

    func testMalformedTokenKeepsThePreviousPreview() {
        KlaviyoSDK().startFormsPreview(validPreviewToken)
        KlaviyoSDK().startFormsPreview("not-a-preview-token")
        XCTAssertEqual(FormsPreviewTokenStore.shared.token, validPreviewToken)
    }
}
