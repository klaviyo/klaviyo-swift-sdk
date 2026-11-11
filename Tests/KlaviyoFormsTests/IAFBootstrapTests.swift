@testable import KlaviyoForms
import JavaScriptCore
import KlaviyoCore
import WebKit
import XCTest

@MainActor
private final class BootstrapDelegate: MockIAFWebViewDelegate {
    var onEvaluation: ((String) -> Void)?

    override func evaluateJavaScript(_ script: String) async throws -> Any? {
        onEvaluation?(script)
        return try await super.evaluateJavaScript(script)
    }
}

@MainActor
final class IAFBootstrapTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        seedCoreStores()
        await AuthTokenManager.shared.unregisterProvider()
        IAFPresentationManager.shared.destroyWebviewAndListeners()
    }

    override func tearDown() async throws {
        IAFPresentationManager.shared.destroyWebviewAndListeners()
        await AuthTokenManager.shared.unregisterProvider()
        try await super.tearDown()
    }

    func testOnsiteLoaderReadsProfileAndJWTRegardlessOfScriptSetOrder() throws {
        let profile = ProfileData(email: "cached@example.com", anonymousId: "cached-anon")
        let model = IAFWebViewModel(url: URL(fileURLWithPath: "/tmp/bootstrap.html"), apiKey: "abc123",
                                   profileData: profile, authToken: "cached.jwt.signature")
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var attributes = {};
        var loadedProfile;
        var loadedJWT;
        var document = {
            head: {
                setAttribute: function(key, value) { attributes[key] = value; },
                appendChild: function(script) {
                    loadedProfile = attributes['data-klaviyo-profile'];
                    loadedJWT = attributes['data-klaviyo-jwt'];
                }
            },
            createElement: function() { return {}; }
        };
        """)
        let scripts = try XCTUnwrap(model.loadScripts).filter { $0.injectionTime == .atDocumentEnd }
        let loaderFirst = scripts.sorted {
            $0.source.contains("script.id = 'klaviyoJS'") && !$1.source.contains("script.id = 'klaviyoJS'")
        }
        for script in loaderFirst {
            context.evaluateScript(script.source)
        }
        XCTAssertNil(context.exception)
        let loadedProfile = try XCTUnwrap(context.objectForKeyedSubscript("loadedProfile")?.toString())
        XCTAssertTrue(loadedProfile.contains("cached@example.com"))
        XCTAssertEqual(context.objectForKeyedSubscript("loadedJWT")?.toString(), "cached.jwt.signature")
    }

    func testCachedTokenReplayDoesNotApplyJWTTwice() async throws {
        let model = IAFWebViewModel(url: URL(fileURLWithPath: "/tmp/bootstrap.html"), apiKey: "abc123",
                                   profileData: nil, authToken: "cached.jwt.signature")
        let delegate = MockIAFWebViewDelegate(viewModel: model)
        model.delegate = delegate
        await model.pushAuthToken("cached.jwt.signature")
        XCTAssertTrue(delegate.evaluatedScripts.isEmpty)
    }

    func testLateJWTWaitsForNavigationCompletion() async throws {
        try await assertLateJWTDelivered(after: .didFinishNavigation)
    }

    func testLateJWTWaitsForNavigationFailure() async throws {
        try await assertLateJWTDelivered(after: .didFailNavigation)
    }

    func testLateJWTWaitsForProvisionalNavigationFailure() async throws {
        try await assertLateJWTDelivered(after: .didFailProvisionalNavigation)
    }

    private func assertLateJWTDelivered(after navigationEvent: WKNavigationEvent) async throws {
        let model = IAFWebViewModel(url: URL(fileURLWithPath: "/tmp/bootstrap.html"), apiKey: "abc123",
                                   profileData: IdentityStore.shared.current)
        let delegate = BootstrapDelegate(viewModel: model)
        model.delegate = delegate
        model.handleNavigationEvent(.didStartProvisionalNavigation)
        await model.pushAuthToken("superseded.jwt.signature")
        await model.pushAuthToken("late.jwt.signature")
        XCTAssertTrue(delegate.evaluatedScripts.isEmpty)
        let installed = expectation(description: "latest token installed once after navigation")
        delegate.onEvaluation = { script in
            if script.contains("late.jwt.signature") { installed.fulfill() }
        }
        model.handleNavigationEvent(navigationEvent)
        await fulfillment(of: [installed], timeout: 2)
        XCTAssertEqual(delegate.evaluatedScripts.filter { $0.contains("data-klaviyo-jwt") }.count, 1)
        XCTAssertFalse(delegate.evaluatedScripts.contains { $0.contains("superseded.jwt.signature") })
    }

    func testWebViewCreationReturnsBeforeSlowProviderCompletes() async throws {
        let (entered, entry) = AsyncStream.makeStream(of: Void.self)
        let (release, completion) = AsyncStream.makeStream(of: Void.self)
        let token = try makeTestJWT()
        await AuthTokenManager.shared.registerProvider {
            entry.yield(())
            _ = await release.first { _ in true }
            return token
        }
        _ = await entered.first { _ in true }
        let started = Date()
        try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")
        let elapsed = Date().timeIntervalSince(started)
        completion.yield(())
        XCTAssertLessThan(elapsed, 0.3)
        XCTAssertNotNil(IAFPresentationManager.shared.viewController)
    }
}
