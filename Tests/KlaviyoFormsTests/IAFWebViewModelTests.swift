//
//  IAFWebViewModelTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/6/25.
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
import Combine
import KlaviyoCore
import WebKit
import XCTest

/// Test-specific subclass that overrides navigation policy to allow all navigation
/// This is required to get these unit tests to pass
private class TestKlaviyoWebViewController: KlaviyoWebViewController {
    override func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        .allow
    }
}

final class IAFWebViewModelTests: XCTestCase {
    // MARK: - Properties

    var viewModel: IAFWebViewModel!
    var initialProfileData: ProfileData!

    // MARK: - Setup

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        // Reset environment to clean state to avoid state persistence from other tests
        environment = KlaviyoEnvironment.test()
        environment.sdkName = { "swift" }
        environment.sdkVersion = { "0.0.1" }
        // Override CDN URL to return the expected production URL for tests
        environment.cdnURL = {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "static.klaviyo.com"
            return components
        }

        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()

        // Reset klaviyoSwiftEnvironment state to clean test state with expected API key
        let testState = KlaviyoState(
            apiKey: "abc123",
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: testState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = {
            testStore.state.eraseToAnyPublisher()
        }

        // Now fetch profile data with clean state
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        let profileData = try await KlaviyoInternal.fetchProfileData()
        initialProfileData = profileData

        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData)
    }

    override func tearDown() {
        viewModel = nil
        initialProfileData = nil
        super.tearDown()
    }

    // MARK: - SDK Attribute Tests

    @MainActor
    func testInjectSdkNameAttribute() {
        // When
        viewModel.initializeLoadScripts()
        let sdkNameScript = viewModel.findScript(containing: ["data-sdk-name", "swift"])

        // Then
        XCTAssertNotNil(sdkNameScript, "SDK name script should be injected")
    }

    @MainActor
    func testInjectSdkVersionAttribute() {
        // When
        viewModel.initializeLoadScripts()
        let sdkVersionScript = viewModel.findScript(containing: ["data-sdk-version", "0.0.1"])

        // Then
        XCTAssertNotNil(sdkVersionScript, "SDK version script should be injected")
    }

    // MARK: - Environment Tests

    @MainActor
    func testInjectFormsDataEnvironmentAttribute() {
        // When
        viewModel.initializeLoadScripts()
        let environmentScript = viewModel.findScript(containing: "data-forms-data-environment")

        // Then
        XCTAssertNil(environmentScript, "Forms data environment script should not be injected when not set")
    }

    @MainActor
    func testInjectFormsDataEnvironmentSetToWeb() async throws {
        // Given
        environment.formsDataEnvironment = { .web }

        // Create a new viewModel with the updated environment
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: nil)

        // When
        viewModel.initializeLoadScripts()
        let environmentScript = viewModel.findScript(containing: ["data-forms-data-environment", "web"])

        // Then
        XCTAssertNotNil(environmentScript, "Forms data environment script should be injected when set to web")
    }

    // MARK: - Handshake Tests

    @MainActor
    func testInjectHandshakeAttribute() throws {
        // When
        viewModel.initializeLoadScripts()
        let handshakeScript = viewModel.findScript(containing: "data-native-bridge-handshake")

        // Then
        XCTAssertNotNil(handshakeScript, "Handshake script should be injected")

        // Extract the handshake string from the script source
        let scriptSource = handshakeScript?.source ?? ""
        let components = scriptSource.components(separatedBy: "'")
        guard components.count >= 2 else {
            XCTFail("Could not find handshake data in script")
            return
        }
        let handshakeString = components[components.count - 2]

        // Verify handshake data
        struct TestableHandshakeData: Codable, Equatable {
            var type: String
            var version: Int
        }

        let expectedHandshakeString =
            """
            [
                {"type":"formWillAppear","version":2},
                {"type":"formDisappeared","version":1},
                {"type":"trackProfileEvent","version":1},
                {"type":"trackAggregateEvent","version":1},
                {"type":"openDeepLink","version":2},
                {"type":"abort","version":1},
                {"type":"lifecycleEvent","version":1},
                {"type":"profileEvent","version":1},
                {"type":"profileMutation","version":1},
                {"type":"jwtMutation","version":1}
            ]
            """
        let expectedData = try XCTUnwrap(expectedHandshakeString.data(using: .utf8))
        let expectedHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: expectedData)

        let actualData = try XCTUnwrap(handshakeString.data(using: .utf8))
        let actualHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: actualData)
        XCTAssertEqual(actualHandshakeData, expectedHandshakeData)
    }

    // MARK: - Auth Token Tests

    @MainActor
    func testInjectAuthTokenAttribute() async throws {
        // Given
        let dummyToken = "header.payload.signature"
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: nil, authToken: dummyToken)

        // When
        viewModel.initializeLoadScripts()
        let authTokenScript = viewModel.findScript(containing: ["data-klaviyo-jwt", dummyToken])

        // Then
        XCTAssertNotNil(authTokenScript, "Auth token script should be injected when authToken is provided")
    }

    @MainActor
    func testAuthTokenScriptNotInjectedWhenTokenIsNil() {
        // When (default viewModel from setUp has authToken: nil)
        viewModel.initializeLoadScripts()
        let authTokenScript = viewModel.findScript(containing: "data-klaviyo-jwt")

        // Then
        XCTAssertNil(authTokenScript, "Auth token script should not be injected when authToken is nil")
    }

    @MainActor
    func testInitialProfileUsesOrderedDocumentStartScript() async throws {
        let profile = ProfileData(email: "initial@example.com", anonymousId: "anon")
        let fileURL = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let model = IAFWebViewModel(url: fileURL, apiKey: "abc123", profileData: profile)

        let scripts: [WKUserScript] = try XCTUnwrap(model.loadScripts)
        let profileScript = try XCTUnwrap(scripts.first { $0.source.contains("data-klaviyo-profile") })
        let profileIndex = try XCTUnwrap(scripts.firstIndex(of: profileScript))
        let klaviyoIndex = try XCTUnwrap(scripts.firstIndex { $0.source.contains("klaviyoJS") })

        XCTAssertEqual(profileScript.injectionTime, .atDocumentStart)
        XCTAssertLessThan(profileIndex, klaviyoIndex)
    }

    // MARK: - Klaviyo JS Tests

    @MainActor
    func testInjectKlaviyoJsScript() {
        // When
        viewModel.initializeLoadScripts()
        let klaviyoJsScript = viewModel.findScript(containing: ["klaviyoJS", "static.klaviyo.com/onsite/js/klaviyo.js"])

        // Then
        XCTAssertNotNil(klaviyoJsScript, "Klaviyo JS script should be injected")
        XCTAssertTrue(klaviyoJsScript?.source.contains("company_id=abc123") ?? false, "Script should include company ID")
        XCTAssertTrue(klaviyoJsScript?.source.contains("env=in-app") ?? false, "Script should include environment")
    }

    // MARK: - Event Handling Tests

    @MainActor
    func testFormWillAppearYieldsPresentLifecycleEvent() async {
        // Given
        let expectation = XCTestExpectation(description: "Form will appear should yield present lifecycle event")

        // Create a task to listen for lifecycle events
        let lifecycleTask = Task {
            for await event in viewModel.formLifecycleStream {
                if case .present = event {
                    expectation.fulfill()
                    break
                }
            }
        }

        // When - simulate a form will appear script message
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formWillAppear",
              "data": {
                "formId": "test123",
                "formName": "Test Form"
              }
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then
        await fulfillment(of: [expectation], timeout: 5.0)
        lifecycleTask.cancel()
    }

    @MainActor
    func testFormDisappearedYieldsDismissLifecycleEvent() async {
        // Given
        let expectation = XCTestExpectation(description: "Form disappeared should yield dismiss lifecycle event")

        // Create a task to listen for lifecycle events
        let lifecycleTask = Task {
            for await event in viewModel.formLifecycleStream {
                if case .dismiss = event {
                    expectation.fulfill()
                    break
                }
            }
        }

        // When - simulate a form disappeared script message with formId and formName
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formDisappeared",
              "data": {
                "formId": "dismiss123",
                "formName": "Dismiss Form"
              }
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then
        await fulfillment(of: [expectation], timeout: 5.0)
        lifecycleTask.cancel()
    }

    @MainActor
    func testFormWillAppearYieldsPresentEvenWithMissingMetadata() async {
        // Given
        let expectation = XCTestExpectation(
            description: "formWillAppear with missing metadata should still yield .present"
        )

        let lifecycleTask = Task {
            for await event in viewModel.formLifecycleStream {
                if case .present = event {
                    expectation.fulfill()
                    break
                }
            }
        }

        // When - simulate a formWillAppear with empty data (no formId/formName)
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formWillAppear",
              "data": {}
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then - .present should still be yielded
        await fulfillment(of: [expectation], timeout: 5.0)
        lifecycleTask.cancel()
    }

    @MainActor
    func testFormDisappearedYieldsDismissEvenWithMissingMetadata() async {
        // Given
        let expectation = XCTestExpectation(
            description: "formDisappeared with missing metadata should still yield .dismiss"
        )

        let lifecycleTask = Task {
            for await event in viewModel.formLifecycleStream {
                if case .dismiss = event {
                    expectation.fulfill()
                    break
                }
            }
        }

        // When - simulate a formDisappeared with empty data
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formDisappeared",
              "data": {}
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then - .dismiss should still be yielded
        await fulfillment(of: [expectation], timeout: 5.0)
        lifecycleTask.cancel()
    }

    @MainActor
    func testAbortEventYieldsAbortLifecycleEvent() async {
        // Given
        let expectation = XCTestExpectation(description: "Abort event should yield abort lifecycle event")
        let abortReason = "test abort reason"

        // Create a task to listen for lifecycle events
        let lifecycleTask = Task {
            for await event in viewModel.formLifecycleStream {
                if case .abort = event {
                    expectation.fulfill()
                    break
                }
            }
        }

        // When - simulate an abort script message
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "abort",
              "data": {
                "reason": "\(abortReason)"
              }
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then
        await fulfillment(of: [expectation], timeout: 5.0)
        lifecycleTask.cancel()
    }

    // MARK: - Token Refresh Tests

    @MainActor
    func testPushAuthTokenUpdatesWebView() async throws {
        // Given — a view model with a wired-up delegate
        let (viewModel, delegate) = try makeTokenViewModel()
        delegate.commitNavigation()
        delegate.finishNavigation()

        // When — a refreshed token is pushed (driven by the presentation
        // manager's refresh subscription in production)
        let refreshedToken = "header.refreshed.signature"
        await viewModel.pushAuthToken(refreshedToken)

        // Then — it is applied as a data-klaviyo-jwt update carrying the token
        let script = try XCTUnwrap(tokenScripts(delegate).first)
        XCTAssertTrue(script.contains(refreshedToken), "Pushed token should update data-klaviyo-jwt with the new value")
    }

    @MainActor
    func testPushAuthTokenAppliesUpdatesInOrder() async throws {
        // Given
        let (viewModel, delegate) = try makeTokenViewModel()
        delegate.commitNavigation()
        delegate.finishNavigation()

        // When — two tokens are pushed sequentially
        let firstToken = "header.first.signature"
        let secondToken = "header.second.signature"
        await viewModel.pushAuthToken(firstToken)
        await viewModel.pushAuthToken(secondToken)

        // Then — both are applied, in order
        let scripts = tokenScripts(delegate)
        XCTAssertEqual(scripts.count, 2)
        XCTAssertTrue(scripts[0].contains(firstToken))
        XCTAssertTrue(scripts[1].contains(secondToken))
    }

    @MainActor
    func testClearQueuedDuringSuspendedTokenEvaluationWins() async throws {
        let (viewModel, delegate) = try makeTokenViewModel()
        let token = "header.pending.signature"
        let evaluationStarted = FormsTestGate()
        let releaseEvaluation = FormsTestGate()
        delegate.commitNavigation()
        delegate.finishNavigation()
        delegate.onEvaluateJavaScriptAsync = { script in
            guard script.contains(token) else { return }
            await evaluationStarted.open()
            await releaseEvaluation.wait()
        }

        let pushTask = Task { await viewModel.pushAuthToken(token) }
        await evaluationStarted.wait()
        let clearTask = Task { await viewModel.clearAuthToken() }
        await Task.yield()
        await releaseEvaluation.open()
        await pushTask.value
        await clearTask.value

        XCTAssertNil(delegate.documentAuthToken)
    }

    @MainActor
    func testClearAuthTokenRemovesJWTFromWebView() async throws {
        let token = "header.initial.signature"
        let (viewModel, delegate) = try makeTokenViewModel(authToken: token)
        delegate.commitNavigation()
        delegate.finishNavigation()

        XCTAssertEqual(delegate.documentAuthToken, token)

        await viewModel.clearAuthToken()

        XCTAssertNil(delegate.documentAuthToken)
    }

    @MainActor
    func testAuthTokenAcquiredBeforeDocumentReadyIsAppliedAfterLoadScripts() async throws {
        let (viewModel, delegate) = try makeTokenViewModel()
        let token = "header.initial.signature"

        delegate.startNavigation()
        delegate.commitNavigation()
        await viewModel.pushAuthToken(token)

        XCTAssertNil(delegate.documentAuthToken)

        let tokenApplied = expectation(description: "token applied after commit")
        delegate.onEvaluateJavaScript = { script in
            if script.contains(token) {
                tokenApplied.fulfill()
            }
        }
        delegate.finishNavigation()

        await fulfillment(of: [tokenApplied], timeout: 1)
        XCTAssertEqual(delegate.documentAuthToken, token)
    }

    @MainActor
    func testCachedTokenIsReconciledAfterDocumentEndScripts() async throws {
        let cachedToken = "header.cached.signature"
        let replacementToken = "header.replacement.signature"
        let (viewModel, delegate) = try makeTokenViewModel(authToken: cachedToken)

        delegate.startNavigation()
        delegate.commitNavigation()
        await viewModel.pushAuthToken(replacementToken)
        let tokenApplied = expectation(description: "replacement token applied")
        delegate.onEvaluateJavaScript = { script in
            if script.contains(replacementToken) {
                tokenApplied.fulfill()
            }
        }
        delegate.finishNavigation()

        await fulfillment(of: [tokenApplied], timeout: 1)
        XCTAssertEqual(delegate.documentAuthToken, replacementToken)
    }

    @MainActor
    func testCachedTokenClearedBeforeCommitIsRemovedAfterDocumentEndScripts() async throws {
        let cachedToken = "header.cached.signature"
        let (viewModel, delegate) = try makeTokenViewModel(authToken: cachedToken)

        delegate.startNavigation()
        await viewModel.clearAuthToken()
        delegate.commitNavigation()
        let tokenCleared = expectation(description: "cached token cleared")
        delegate.onEvaluateJavaScript = { script in
            if script == "document.head.removeAttribute('data-klaviyo-jwt');" {
                tokenCleared.fulfill()
            }
        }
        delegate.finishNavigation()

        await fulfillment(of: [tokenCleared], timeout: 1)
        XCTAssertNil(delegate.documentAuthToken)
    }

    @MainActor
    func testTokenBufferedDuringFailedNavigationIsAppliedToSurvivingDocument() async throws {
        let initialToken = "header.initial.signature"
        let replacementToken = "header.replacement.signature"
        let (viewModel, delegate) = try makeTokenViewModel(authToken: initialToken)

        delegate.startNavigation()
        delegate.commitNavigation()
        delegate.finishNavigation()
        XCTAssertEqual(delegate.documentAuthToken, initialToken)

        delegate.startNavigation()
        await viewModel.pushAuthToken(replacementToken)
        XCTAssertEqual(delegate.documentAuthToken, initialToken)

        let tokenApplied = expectation(description: "replacement token applied to surviving document")
        delegate.onEvaluateJavaScript = { script in
            if script.contains(replacementToken) {
                tokenApplied.fulfill()
            }
        }
        delegate.failProvisionalNavigation()

        await fulfillment(of: [tokenApplied], timeout: 1)
        XCTAssertEqual(delegate.documentAuthToken, replacementToken)
    }

    @MainActor
    func testAuthTokenDeliveredToPreviousDocumentIsRedeliveredAfterDocumentReady() async throws {
        let (viewModel, delegate) = try makeTokenViewModel()
        let token = "header.same.signature"
        delegate.commitNavigation()
        delegate.finishNavigation()
        await viewModel.pushAuthToken(token)

        let tokenApplied = expectation(description: "token applied to new document")
        delegate.onEvaluateJavaScript = { script in
            if script.contains(token) {
                tokenApplied.fulfill()
            }
        }
        delegate.startNavigation()
        delegate.commitNavigation()
        delegate.finishNavigation()

        await fulfillment(of: [tokenApplied], timeout: 1)
        XCTAssertEqual(delegate.documentAuthToken, token)
    }

    @MainActor
    func testProfileChangeAppliesProfileBeforeReplacementToken() async throws {
        let tokenA = try makeFormsJWT(subject: "profile-A")
        let tokenB = try makeFormsJWT(subject: "profile-B")
        let tokenSource = FormsTokenSource(tokenA)
        await AuthTokenManager.shared.registerProvider { await tokenSource.value }
        _ = try await AuthTokenManager.shared.currentToken(mode: .background)
        await tokenSource.set(tokenB)

        let profileA = ProfileData(email: "a@example.com", anonymousId: "anon-a")
        let profileB = ProfileData(email: "b@example.com", anonymousId: "anon-b")
        let stateSubject = CurrentValueSubject<KlaviyoState, Never>(
            KlaviyoState(
                apiKey: "abc123",
                email: profileA.email,
                anonymousId: profileA.anonymousId,
                queue: [],
                initalizationState: .initialized
            )
        )
        klaviyoSwiftEnvironment.statePublisher = { stateSubject.eraseToAnyPublisher() }
        KlaviyoInternal.resetProfileDataSubject()

        let fileURL = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let model = IAFWebViewModel(url: fileURL, apiKey: "abc123", profileData: profileA)
        let delegate = MockIAFWebViewDelegate(viewModel: model)
        model.delegate = delegate
        delegate.commitNavigation()
        delegate.finishNavigation()
        let replacementApplied = expectation(description: "replacement token applied")
        delegate.onEvaluateJavaScript = { script in
            if script.contains(tokenB) {
                replacementApplied.fulfill()
            }
        }

        AuthTokenCommandQueue.shared.enqueue(.clearTokenState)
        stateSubject.send(
            KlaviyoState(
                apiKey: "abc123",
                email: profileB.email,
                anonymousId: profileB.anonymousId,
                queue: [],
                initalizationState: .initialized
            )
        )
        await fulfillment(of: [replacementApplied], timeout: 1)

        let profileIndex = try XCTUnwrap(
            delegate.evaluatedScripts.firstIndex { $0.contains("b@example.com") }
        )
        let tokenIndex = try XCTUnwrap(
            delegate.evaluatedScripts.firstIndex { $0.contains(tokenB) }
        )
        XCTAssertLessThan(profileIndex, tokenIndex)

        await AuthTokenManager.shared.unregisterProvider()
    }

    @MainActor
    func testProfileChangeToAnonymousClearsAuthWithoutRefetching() async throws {
        let token = try makeFormsJWT(subject: "identified")
        let tokenSource = FormsTokenSource(token)
        await AuthTokenManager.shared.registerProvider { await tokenSource.value }
        _ = try await AuthTokenManager.shared.currentToken(mode: .background)

        let profile = ProfileData(email: "a@example.com", anonymousId: "anon-a")
        let stateSubject = CurrentValueSubject<KlaviyoState, Never>(
            KlaviyoState(
                apiKey: "abc123",
                email: profile.email,
                anonymousId: profile.anonymousId,
                queue: [],
                initalizationState: .initialized
            )
        )
        klaviyoSwiftEnvironment.statePublisher = { stateSubject.eraseToAnyPublisher() }
        KlaviyoInternal.resetProfileDataSubject()

        let fileURL = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let model = IAFWebViewModel(
            url: fileURL,
            apiKey: "abc123",
            profileData: profile,
            authToken: token
        )
        let delegate = MockIAFWebViewDelegate(viewModel: model)
        model.delegate = delegate
        delegate.commitNavigation()
        delegate.finishNavigation()
        let authCleared = expectation(description: "auth cleared")
        delegate.onEvaluateJavaScript = { script in
            if script == "document.head.removeAttribute('data-klaviyo-jwt');" {
                authCleared.fulfill()
            }
        }

        AuthTokenCommandQueue.shared.enqueue(.clearTokenState)
        stateSubject.send(
            KlaviyoState(
                apiKey: "abc123",
                anonymousId: "anon-b",
                queue: [],
                initalizationState: .initialized
            )
        )
        await fulfillment(of: [authCleared], timeout: 1)

        await AuthTokenManager.shared.unregisterProvider()
    }
}

extension IAFWebViewModel {
    @MainActor
    fileprivate func findScript(containing text: String) -> WKUserScript? {
        loadScripts?.first { script in
            script.source.contains(text)
        }
    }

    @MainActor
    fileprivate func findScript(containing texts: [String]) -> WKUserScript? {
        loadScripts?.first { script in
            texts.allSatisfy { text in
                script.source.contains(text)
            }
        }
    }
}

// MARK: - Token refresh test helpers

extension IAFWebViewModelTests {
    /// Builds a view model with a wired-up mock delegate, so `pushAuthToken`
    /// tests can observe the resulting `evaluateJavaScript` calls.
    @MainActor
    private func makeTokenViewModel(
        authToken: String? = nil
    ) throws -> (IAFWebViewModel, MockIAFWebViewDelegate) {
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let viewModel = IAFWebViewModel(
            url: fileUrl,
            apiKey: "abc123",
            profileData: initialProfileData,
            authToken: authToken
        )
        let delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
        return (viewModel, delegate)
    }

    /// The auth-token update scripts among everything the delegate has evaluated.
    /// Filters out the incidental `data-klaviyo-profile` updates that the view
    /// model's profile subscription emits during setup, isolating the
    /// token-update behavior under test.
    @MainActor
    private func tokenScripts(_ delegate: MockIAFWebViewDelegate) -> [String] {
        delegate.evaluatedScripts.filter { $0.contains("data-klaviyo-jwt") }
    }
}
