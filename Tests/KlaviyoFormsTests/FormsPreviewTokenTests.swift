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
let otherPreviewToken = "ZYXWVUTSRQPONMLKJIHGFEDCBAzyxwvutsrqponm987"

@MainActor
final class InAppFormsConfigPreviewTokenTests: XCTestCase {
    private var store: FormsPreviewTokenStore!

    override func setUp() async throws {
        try await super.setUp()
        store = FormsPreviewTokenStore()
    }

    func testApplyConfigStoresToken() {
        store.applyConfigurationToken(InAppFormsConfig(previewToken: validPreviewToken).previewToken)
        XCTAssertEqual(store.token, validPreviewToken)
    }

    func testConfigDescriptionRedactsToken() {
        let config = InAppFormsConfig(previewToken: validPreviewToken)
        XCTAssertFalse(String(describing: config).contains(validPreviewToken))
        XCTAssertFalse(String(reflecting: config).contains(validPreviewToken))
    }

    func testConfigCarriesPreviewToken() {
        XCTAssertNil(InAppFormsConfig().previewToken)
        let config = InAppFormsConfig(sessionTimeoutDuration: 10, previewToken: validPreviewToken)
        XCTAssertEqual(config.previewToken, validPreviewToken)
        XCTAssertEqual(config.sessionTimeoutDuration, 10)
    }
}

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

    private func previewTokenScripts(in delegate: MockIAFWebViewDelegate) -> [String] {
        delegate.evaluatedScripts.filter { $0.contains("data-klaviyo-forms-preview-token") }
    }

    private func completeHandshake(_ viewModel: IAFWebViewModel) {
        viewModel.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: #"{"type":"handShook","data":{}}"#
        ))
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

    func testTokenChangeBeforeHandshakeUpdatesLoadScriptAndIsPushedAfterHandshake() async throws {
        let (viewModel, delegate) = try makeViewModel()
        _ = try? await viewModel.establishHandshake(timeout: 0.01)

        store.setToken(validPreviewToken)
        XCTAssertTrue(previewTokenScripts(in: delegate).isEmpty, "No live write before the handshake")
        XCTAssertTrue(try XCTUnwrap(previewTokenLoadScript(in: viewModel)).source.contains(validPreviewToken))

        completeHandshake(viewModel)
        await assertEventually { self.previewTokenScripts(in: delegate).contains { $0.contains(validPreviewToken) } }
    }

    func testTokenRenderedAtLoadIsNotPushedAgainAfterHandshake() async throws {
        store.setToken(validPreviewToken)
        let (viewModel, delegate) = try makeViewModel()
        _ = try? await viewModel.establishHandshake(timeout: 0.01)
        completeHandshake(viewModel)
        await Task.yield()
        XCTAssertTrue(previewTokenScripts(in: delegate).isEmpty)
    }

    func testLiveChangesAfterHandshakeReachThePage() async throws {
        let (viewModel, delegate) = try makeViewModel()
        completeHandshake(viewModel)

        store.setToken(validPreviewToken)
        await assertEventually { self.previewTokenScripts(in: delegate).count == 1 }
        store.setToken(nil)
        await assertEventually { self.previewTokenScripts(in: delegate).count == 2 }

        let scripts = previewTokenScripts(in: delegate)
        XCTAssertEqual(scripts.count, 2)
        XCTAssertTrue(scripts.first?.contains(validPreviewToken) ?? false)
        XCTAssertTrue(scripts.last?.contains("data-klaviyo-forms-preview-token', \"\"") ?? false)
        XCTAssertNil(previewTokenLoadScript(in: viewModel), "A cleared token is not reloaded")
    }

    func testPreviewEndedClearsStoredTokenAndBlocksItFromConfig() async throws {
        store.setToken(validPreviewToken)
        let (viewModel, _) = try makeViewModel()
        viewModel.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: #"{"type":"formsPreviewEnded","data":{"reason":"expired"}}"#
        ))
        XCTAssertNil(store.token)

        store.applyConfigurationToken(validPreviewToken)
        XCTAssertNil(store.token, "A configured token whose preview ended is not revived")
    }
}

@MainActor
final class FormsPreviewTokenPublicAPITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        FormsPreviewTokenStore.shared.clear()
    }

    override func tearDown() async throws {
        FormsPreviewTokenStore.shared.clear()
        try await super.tearDown()
    }

    func testSetterStoresAndClearsToken() {
        KlaviyoSDK().setFormsPreviewToken(validPreviewToken)
        XCTAssertEqual(FormsPreviewTokenStore.shared.token, validPreviewToken)
        KlaviyoSDK().setFormsPreviewToken(nil)
        XCTAssertNil(FormsPreviewTokenStore.shared.token)
    }

    func testInvalidSetterValueClearsPreviousToken() {
        KlaviyoSDK().setFormsPreviewToken(validPreviewToken)
        KlaviyoSDK().setFormsPreviewToken("not-a-preview-token")
        XCTAssertNil(FormsPreviewTokenStore.shared.token)
    }
}
