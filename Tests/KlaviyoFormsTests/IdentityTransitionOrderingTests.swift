//
//  IdentityTransitionOrderingTests.swift
//  klaviyo-swift-sdk
//
//  Drives identity changes through the KlaviyoSwift reducer into a Forms page and
//  checks that the page always receives the new profile before the token for it.
//

@testable import KlaviyoCore
@testable import KlaviyoForms
@testable import KlaviyoSwift
import XCTest

@MainActor
final class IdentityTransitionOrderingTests: XCTestCase {
    private struct Path {
        let name: String
        let start: KlaviyoState
        let action: KlaviyoAction
        let incomingEmail: String
    }

    private var store: Store<KlaviyoState, KlaviyoAction>!
    private var provider: ScriptedTokenProvider!
    private var manager: AuthTokenManager!
    private var presentationManager: IAFPresentationManager!
    private var viewModel: IAFWebViewModel!
    private var delegate: MockIAFWebViewDelegate!

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        SharedStoreMirror.reset()
        provider = ScriptedTokenProvider()
        manager = makeUnboundedAuthTokenManager()
        presentationManager = IAFPresentationManager(viewController: nil)
    }

    override func tearDown() async throws {
        presentationManager.destroyWebView()
        await manager.unregisterProvider()
        SharedStoreMirror.reset()
        presentationManager = nil
        manager = nil
        viewModel = nil
        delegate = nil
        store = nil
        try await super.tearDown()
    }

    private var paths: [Path] {
        [
            Path(
                name: "bulk replacement",
                start: state(email: "a@x.com"),
                action: .enqueueProfile(Profile(email: "b@x.com")),
                incomingEmail: "b@x.com"
            ),
            Path(
                name: "scalar replacement",
                start: state(email: "a@x.com", phoneNumber: "+15551234567"),
                action: .setEmail("b@x.com"),
                incomingEmail: "b@x.com"
            ),
            Path(
                name: "anonymous to identified",
                start: state(),
                action: .setEmail("b@x.com"),
                incomingEmail: "b@x.com"
            )
        ]
    }

    // MARK: - Live page

    func testLivePageReceivesNewProfileBeforeItsToken() async throws {
        for path in paths {
            try await startStore(path.start)
            let outgoingToken = try? await manager.currentToken(mode: .background)
            await makeViewModel(authToken: outgoingToken)

            send(path.action)
            await delegate.awaitScript(containing: "data-klaviyo-jwt")

            let tokenScripts = delegate.authTokenScripts
            XCTAssertEqual(tokenScripts.count, 1, path.name)
            if let outgoingToken {
                XCTAssertFalse(tokenScripts.contains { $0.contains(outgoingToken) }, path.name)
            }
            assertProfileBeforeToken(in: delegate.evaluatedScripts, email: path.incomingEmail, path.name)
            await resetProvider()
        }
    }

    // MARK: - Fresh page

    func testFreshPageLoadsNewProfileBeforeItsToken() async throws {
        for path in paths {
            try await startStore(path.start)
            let outgoingToken = try? await manager.currentToken(mode: .background)

            send(path.action)
            try await makeFreshViewModel()

            let identityScripts = loadScriptSources.filter { $0.contains("data-klaviyo-jwt") }
            XCTAssertEqual(identityScripts.count, 1, path.name)
            if let outgoingToken {
                XCTAssertFalse(identityScripts.contains { $0.contains(outgoingToken) }, path.name)
            }
            assertProfileBeforeToken(in: identityScripts, email: path.incomingEmail, path.name)
            await resetProvider()
        }
    }

    func testColdLaunchPageLoadsQueuedProfileBeforeItsToken() async throws {
        try await startStore(KlaviyoState(apiKey: "abc123", queue: [], initalizationState: .initializing))

        send(.enqueueProfile(Profile(email: "b@x.com")))
        send(.completeInitialization(state(email: "a@x.com")))
        try await makeFreshViewModel()

        let identityScripts = loadScriptSources.filter { $0.contains("data-klaviyo-jwt") }
        XCTAssertEqual(identityScripts.count, 1)
        XCTAssertFalse(identityScripts.contains { $0.contains("a@x.com") })
        assertProfileBeforeToken(in: identityScripts, email: "b@x.com", "cold launch")
    }
}

// MARK: - Helpers

extension IdentityTransitionOrderingTests {
    private func state(email: String? = nil, phoneNumber: String? = nil) -> KlaviyoState {
        KlaviyoState(
            apiKey: "abc123",
            email: email,
            anonymousId: "anon-A",
            phoneNumber: phoneNumber,
            queue: [],
            initalizationState: .initialized
        )
    }

    /// Builds a store for `state`, mirrors it into the shared Core stores, and registers
    /// ``provider`` with ``manager``.
    private func startStore(_ state: KlaviyoState) async throws {
        SharedStoreMirror.reset()
        let store = Store(initialState: state, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { store.state.eraseToAnyPublisher() }
        SharedStoreMirror.setup()
        self.store = store
        let provider = try XCTUnwrap(provider)
        await manager.registerProvider { try await provider.provide() }
    }

    private func send(_ action: KlaviyoAction) {
        _ = store.send(action)
    }

    private func resetProvider() async {
        await manager.unregisterProvider()
        provider = ScriptedTokenProvider()
    }

    private func makeViewModel(authToken: String?) async {
        let updates = await manager.refreshes()
        let viewModel = IAFWebViewModel(
            url: URL(string: "https://example.com")!,
            apiKey: "abc123",
            profileData: IdentityStore.shared.current,
            authToken: authToken,
            authTokenManager: manager
        )
        let delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
        self.viewModel = viewModel
        self.delegate = delegate
        presentationManager.prepareTokenDelivery(
            for: viewModel,
            initialToken: authToken,
            initialProfile: IdentityStore.shared.current,
            updates: updates,
            from: manager
        )
        presentationManager.startTokenDelivery()
    }

    /// Builds a page the way `IAFPresentationManager` does: the current profile plus the
    /// token the manager serves for it.
    private func makeFreshViewModel() async throws {
        var token: String?
        for _ in 0..<3 where token == nil {
            token = try? await manager.currentToken(mode: .background)
        }
        try await makeViewModel(authToken: XCTUnwrap(token))
    }

    private var loadScriptSources: [String] {
        viewModel.loadScripts?.map(\.source) ?? []
    }

    /// Asserts that `scripts`, in order, write a profile carrying `email` before any token.
    private func assertProfileBeforeToken(
        in scripts: [String],
        email: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lines = scripts.flatMap { $0.components(separatedBy: "\n") }
        let profileIndex = lines.firstIndex { $0.contains("data-klaviyo-profile") && $0.contains(email) }
        let tokenIndex = lines.firstIndex { $0.contains("data-klaviyo-jwt") }
        guard let profileIndex, let tokenIndex else {
            XCTFail("expected a profile write and a token write: \(message)", file: file, line: line)
            return
        }
        XCTAssertLessThan(profileIndex, tokenIndex, message, file: file, line: line)
    }
}
