@testable import KlaviyoForms
import KlaviyoCore
import XCTest

@MainActor
private final class ProfileAuthOrderingDelegate: MockIAFWebViewDelegate {
    var onEvaluation: ((String) -> Void)?
    var clearStarted: XCTestExpectation?
    private var clearContinuation: CheckedContinuation<Void, Never>?

    func resumeClear() {
        clearContinuation?.resume()
        clearContinuation = nil
        clearStarted = nil
    }

    override func evaluateJavaScript(_ script: String) async throws -> Any? {
        if script.contains("document.head.removeAttribute('data-klaviyo-jwt')"), clearStarted != nil {
            await withCheckedContinuation { continuation in
                clearContinuation = continuation
                clearStarted?.fulfill()
            }
        }
        onEvaluation?(script)
        return try await super.evaluateJavaScript(script)
    }
}

final class IAFProfileAuthOrderingTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        seedCoreStores()
    }

    @MainActor
    func testProfileReplacementClearsOutgoingJWTBeforePublishingProfile() async throws {
        let outgoingProfile = ProfileData(email: "outgoing@example.com", anonymousId: "outgoing-anon")
        let resetProfile = ProfileData(anonymousId: "replacement-anon")
        let replacementProfile = ProfileData(email: "replacement@example.com", anonymousId: "replacement-anon")
        IdentityStore.shared.update(outgoingProfile)
        let model = IAFWebViewModel(
            url: URL(fileURLWithPath: "/tmp/IAFProfileAuthOrderingTests.html"),
            apiKey: "abc123",
            profileData: outgoingProfile,
            authToken: "outgoing.jwt.signature"
        )
        let delegate = ProfileAuthOrderingDelegate(viewModel: model)
        model.delegate = delegate
        let replacementApplied = expectation(description: "replacement profile applied")
        delegate.onEvaluation = { script in
            if script.contains("replacement@example.com") {
                replacementApplied.fulfill()
            }
        }

        await AuthTokenManager.shared.clearTokenState()
        IdentityStore.shared.update(resetProfile)
        IdentityStore.shared.update(replacementProfile)
        await fulfillment(of: [replacementApplied], timeout: 30)

        let clearIndex = try XCTUnwrap(delegate.evaluatedScripts.firstIndex {
            $0.contains("document.head.removeAttribute('data-klaviyo-jwt')")
        })
        let profileIndex = try XCTUnwrap(delegate.evaluatedScripts.firstIndex {
            $0.contains("replacement@example.com")
        })
        XCTAssertLessThan(clearIndex, profileIndex)
        let firstProfileIndex = try XCTUnwrap(delegate.evaluatedScripts.firstIndex {
            $0.contains("data-klaviyo-profile")
        })
        XCTAssertLessThan(clearIndex, firstProfileIndex)
    }

    @MainActor
    func testSameUserProfileMutationKeepsMatchingJWT() async throws {
        let initialProfile = ProfileData(email: "first@example.com", anonymousId: "same-anon")
        let updatedProfile = ProfileData(email: "second@example.com", anonymousId: "same-anon")
        IdentityStore.shared.update(initialProfile)
        let model = IAFWebViewModel(
            url: URL(fileURLWithPath: "/tmp/IAFProfileAuthOrderingTests.html"),
            apiKey: "abc123",
            profileData: initialProfile,
            authToken: "same.jwt.signature"
        )
        let delegate = ProfileAuthOrderingDelegate(viewModel: model)
        model.delegate = delegate
        let profileApplied = expectation(description: "same-user profile applied")
        delegate.onEvaluation = { script in
            if script.contains("second@example.com") { profileApplied.fulfill() }
        }

        IdentityStore.shared.update(updatedProfile)
        await fulfillment(of: [profileApplied], timeout: 30)

        XCTAssertFalse(delegate.evaluatedScripts.contains {
            $0.contains("document.head.removeAttribute('data-klaviyo-jwt')")
        })
    }

    @MainActor
    func testProfileReplacementWaitsForInFlightJWTRemoval() async throws {
        let outgoingProfile = ProfileData(email: "outgoing@example.com", anonymousId: "outgoing-anon")
        let replacementProfile = ProfileData(email: "replacement@example.com", anonymousId: "replacement-anon")
        IdentityStore.shared.update(outgoingProfile)
        let model = IAFWebViewModel(
            url: URL(fileURLWithPath: "/tmp/IAFProfileAuthOrderingTests.html"),
            apiKey: "abc123",
            profileData: outgoingProfile,
            authToken: "outgoing.jwt.signature"
        )
        let delegate = ProfileAuthOrderingDelegate(viewModel: model)
        model.delegate = delegate
        let clearStarted = expectation(description: "JWT removal started")
        let prematureProfile = expectation(description: "replacement profile applied before JWT removal")
        prematureProfile.isInverted = true
        let profileApplied = expectation(description: "replacement profile applied")
        delegate.clearStarted = clearStarted
        var clearReleased = false
        delegate.onEvaluation = { script in
            guard script.contains("replacement@example.com") else { return }
            if clearReleased {
                profileApplied.fulfill()
            } else {
                prematureProfile.fulfill()
            }
        }

        let clearTask = Task { await model.clearAuthToken() }
        await fulfillment(of: [clearStarted], timeout: 30)
        IdentityStore.shared.update(replacementProfile)
        await fulfillment(of: [prematureProfile], timeout: 0.5)
        clearReleased = true
        delegate.resumeClear()
        await clearTask.value
        await fulfillment(of: [profileApplied], timeout: 30)
    }
}
