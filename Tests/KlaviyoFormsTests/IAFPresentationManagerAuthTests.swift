//
//  IAFPresentationManagerAuthTests.swift
//  KlaviyoFormsTests
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
import Combine
import KlaviyoCore
import XCTest

final class IAFPresentationManagerAuthTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()
        let state = KlaviyoState(
            apiKey: "abc123",
            anonymousId: "anon",
            queue: [],
            initalizationState: .initialized
        )
        let stateSubject = CurrentValueSubject<KlaviyoState, Never>(state)
        klaviyoSwiftEnvironment.statePublisher = { stateSubject.eraseToAnyPublisher() }
    }

    @MainActor
    override func tearDown() async throws {
        IAFPresentationManager.shared.destroyWebviewAndListeners()
        await AuthTokenManager.shared.unregisterProvider()
    }

    @MainActor
    func testWebViewCreationDoesNotWaitForInteractiveTokenTimeout() async throws {
        let token = try makeFormsJWT(subject: "initial")
        let providerEntered = FormsTestGate()
        let releaseProvider = FormsTestGate()
        await AuthTokenManager.shared.registerProvider {
            await providerEntered.open()
            await releaseProvider.wait()
            return token
        }
        await providerEntered.wait()

        do {
            try await withTimeout(seconds: 0.4) {
                try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")
            }
        } catch {
            await releaseProvider.open()
            throw error
        }

        XCTAssertNotNil(IAFPresentationManager.shared.viewController)
        await releaseProvider.open()
    }
}
