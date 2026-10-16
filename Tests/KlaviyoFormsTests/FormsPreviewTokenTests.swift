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
final class FormsPreviewTokenStoreTests: XCTestCase {
    private var store: FormsPreviewTokenStore!

    override func setUp() async throws {
        try await super.setUp()
        store = FormsPreviewTokenStore()
    }

    func testStoresValidToken() {
        store.setToken(validPreviewToken)
        XCTAssertEqual(store.token, validPreviewToken)
    }

    func testSurroundingWhitespaceIsTrimmed() {
        for padded in [validPreviewToken + "\n", "  " + validPreviewToken + " ", "\t" + validPreviewToken] {
            store.clear()
            store.setToken(padded)
            XCTAssertEqual(store.token, validPreviewToken)
        }
    }

    func testNilEmptyAndWhitespaceClearTheToken() {
        for clearValue in [nil, "", "   "] as [String?] {
            store.setToken(validPreviewToken)
            store.setToken(clearValue)
            XCTAssertNil(store.token)
        }
    }

    func testMalformedTokensAreDroppedAndClearThePreviousToken() {
        let malformed = [
            String(validPreviewToken.dropLast()),
            validPreviewToken + "a",
            String(validPreviewToken.dropLast()) + "=",
            String(validPreviewToken.dropLast(2)) + "'>",
            String(validPreviewToken.prefix(20)) + " " + validPreviewToken.dropFirst(21)
        ]
        for token in malformed {
            store.setToken(otherPreviewToken)
            store.setToken(token)
            XCTAssertNil(store.token, "Expected \(token) to be rejected")
        }
    }

    func testPublishesOnlyOnChange() {
        var published: [String?] = []
        let cancellable = store.$token.dropFirst().sink { published.append($0) }
        store.setToken(validPreviewToken)
        store.setToken(validPreviewToken)
        store.clear()
        store.clear()
        cancellable.cancel()
        XCTAssertEqual(published, [validPreviewToken, nil])
    }

    func testApplyConfigStoresToken() {
        store.apply(InAppFormsConfig(previewToken: validPreviewToken))
        XCTAssertEqual(store.token, validPreviewToken)
    }

    func testApplyConfigWithNewTokenReplacesStoredToken() {
        store.apply(InAppFormsConfig(previewToken: validPreviewToken))
        store.apply(InAppFormsConfig(previewToken: otherPreviewToken))
        XCTAssertEqual(store.token, otherPreviewToken)
    }

    func testApplyConfigWithoutTokenKeepsTokenFromSetter() {
        store.setToken(validPreviewToken)
        store.apply(InAppFormsConfig())
        store.apply(InAppFormsConfig(previewToken: ""))
        XCTAssertEqual(store.token, validPreviewToken)
    }

    func testApplyConfigWithInvalidTokenClearsToken() {
        store.setToken(validPreviewToken)
        store.apply(InAppFormsConfig(previewToken: "<script>"))
        XCTAssertNil(store.token)
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
        await delegate.waitForScript(containing: validPreviewToken)
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
        await delegate.waitForScript(containing: validPreviewToken)
        store.setToken(nil)
        await delegate.waitForScript(containing: "data-klaviyo-forms-preview-token', \"\"")

        XCTAssertEqual(previewTokenScripts(in: delegate).count, 2)
        XCTAssertNil(previewTokenLoadScript(in: viewModel), "A cleared token is not reloaded")
    }

    func testPreviewEndedClearsStoredToken() async throws {
        store.setToken(validPreviewToken)
        let (viewModel, _) = try makeViewModel()
        viewModel.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: #"{"type":"formsPreviewEnded","data":{"reason":"expired"}}"#
        ))
        XCTAssertNil(store.token)
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
