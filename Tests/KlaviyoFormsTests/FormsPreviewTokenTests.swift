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

    func testPreviewLinkWithValidTokenSetsItAndReturnsTrue() throws {
        let link = try XCTUnwrap(URL(string: "myapp://home?utm=qr&klaviyo-forms-preview=\(validPreviewToken)"))
        XCTAssertTrue(KlaviyoSDK().handleFormsPreviewLink(link))
        XCTAssertEqual(FormsPreviewTokenStore.shared.token, validPreviewToken)

        let universal = try XCTUnwrap(URL(string: "https://shop.example.com/x?klaviyo-forms-preview=\(otherPreviewToken)"))
        XCTAssertTrue(KlaviyoSDK().handleFormsPreviewLink(universal))
        XCTAssertEqual(FormsPreviewTokenStore.shared.token, otherPreviewToken)
    }

    func testPreviewLinkWithoutParameterOrWithMalformedTokenChangesNothing() throws {
        KlaviyoSDK().startFormsPreview(validPreviewToken)

        XCTAssertFalse(try KlaviyoSDK().handleFormsPreviewLink(XCTUnwrap(URL(string: "myapp://home?other=1"))))
        XCTAssertFalse(try KlaviyoSDK().handleFormsPreviewLink(XCTUnwrap(URL(string: "myapp://x?klaviyo-forms-preview=short"))))
        let padded = try XCTUnwrap(URL(string: "myapp://x?klaviyo-forms-preview=%20\(validPreviewToken)"))
        XCTAssertFalse(KlaviyoSDK().handleFormsPreviewLink(padded))

        XCTAssertEqual(FormsPreviewTokenStore.shared.token, validPreviewToken)
    }

    func testMalformedTokenKeepsThePreviousPreview() {
        KlaviyoSDK().startFormsPreview(validPreviewToken)
        KlaviyoSDK().startFormsPreview("not-a-preview-token")
        XCTAssertEqual(FormsPreviewTokenStore.shared.token, validPreviewToken)
    }
}
