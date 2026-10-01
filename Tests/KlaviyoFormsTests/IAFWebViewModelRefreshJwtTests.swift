//
//  IAFWebViewModelRefreshJwtTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
@testable import KlaviyoForms
import Combine
import XCTest

@MainActor
final class IAFWebViewModelRefreshJwtTests: XCTestCase {
    func testOverlappingSignalsShareOneRefreshUntilItFinishes() async throws {
        let token = try makeTestJWT()
        let counter = InvocationCounter()
        let fetchStarted = Latch()
        let releaseFetch = Latch()
        let authTokenManager = AuthTokenManager(
            lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { Empty().eraseToAnyPublisher() }),
            currentDate: { Date() }
        )
        await authTokenManager.registerProvider {
            await counter.increment()
            await fetchStarted.open()
            await releaseFetch.wait()
            return token
        }
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let viewModel = IAFWebViewModel(
            url: fileUrl,
            apiKey: "abc123",
            profileData: nil,
            authTokenManager: authTokenManager
        )
        // The eager warm-up fetch is now parked inside the provider.
        await fetchStarted.wait()

        viewModel.receiveRefreshJwt()
        let firstRefresh = try XCTUnwrap(viewModel.pendingAuthTokenRefresh)
        viewModel.receiveRefreshJwt()
        XCTAssertEqual(viewModel.pendingAuthTokenRefresh, firstRefresh, "the second signal must be dropped")

        await releaseFetch.open()
        await firstRefresh.value
        XCTAssertNil(viewModel.pendingAuthTokenRefresh)
        let invocationsBefore = await counter.value

        viewModel.receiveRefreshJwt()
        await viewModel.pendingAuthTokenRefresh?.value
        let invocationsAfter = await counter.value
        XCTAssertEqual(
            invocationsAfter,
            invocationsBefore + 1,
            "a signal after the refresh finished must start a new one"
        )
    }
}
