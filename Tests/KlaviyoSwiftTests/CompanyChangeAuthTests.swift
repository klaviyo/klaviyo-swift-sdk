@testable import KlaviyoCore
@testable import KlaviyoSwift
import Combine
import Foundation
import XCTest

final class CompanyChangeAuthTests: XCTestCase {
    private var subscription: AnyCancellable?

    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        await AuthTokenManager.shared.unregisterProvider()
    }

    @MainActor
    override func tearDown() async throws {
        subscription?.cancel()
        subscription = nil
        await AuthTokenManager.shared.unregisterProvider()
    }

    @MainActor
    func testCompanyChangeClearsCachedTokenBeforePublishingNewCompany() async throws {
        let tokenA = try makeToken(subject: "A")
        let tokenB = try makeToken(subject: "B")
        let source = CompanyTokenSource(tokenA)
        await AuthTokenManager.shared.registerProvider { await source.fetch() }
        let initialToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(initialToken, tokenA)

        let store = Store(initialState: companyState(), reducer: KlaviyoReducer())
        let publishedB = expectation(description: "company B published")
        publishedB.assertForOverFulfill = false
        subscription = store.state.dropFirst().sink { state in
            if state.apiKey == "B", state.initalizationState == .initialized {
                publishedB.fulfill()
            }
        }

        await source.setToken(tokenB)
        _ = store.send(.initialize("B"))
        XCTAssertEqual(store.state.value.apiKey, "A")
        await fulfillment(of: [publishedB], timeout: 3)
        let switchedToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        let fetchCount = await source.invocations
        XCTAssertEqual(switchedToken, tokenB)
        XCTAssertEqual(fetchCount, 2)
    }

    @MainActor
    func testLateCompanyATokenCannotBecomeCompanyBToken() async throws {
        let tokenA = try makeToken(subject: "A")
        let tokenB = try makeToken(subject: "B")
        let source = CompanyTokenSource(tokenA, holdFirstFetch: true)
        await AuthTokenManager.shared.registerProvider { await source.fetch() }
        await source.waitForFirstFetch()
        let heldRequest = Task { try await AuthTokenManager.shared.currentToken(mode: .background) }

        let store = Store(initialState: companyState(), reducer: KlaviyoReducer())
        let publishedB = expectation(description: "company B published")
        publishedB.assertForOverFulfill = false
        subscription = store.state.dropFirst().sink { state in
            if state.apiKey == "B", state.initalizationState == .initialized {
                publishedB.fulfill()
            }
        }

        await source.setToken(tokenB)
        _ = store.send(.initialize("B"))
        await fulfillment(of: [publishedB], timeout: 3)
        await source.releaseFirstFetch()

        if case let .success(token) = await heldRequest.result {
            XCTAssertNotEqual(token, tokenA)
        }
        let switchedToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        let fetchCount = await source.invocations
        XCTAssertEqual(switchedToken, tokenB)
        XCTAssertEqual(fetchCount, 2)
    }

    @MainActor
    func testSameKeyInitializationKeepsCachedTokenAndProviderFetchCount() async throws {
        let tokenA = try makeToken(subject: "A")
        let source = CompanyTokenSource(tokenA)
        await AuthTokenManager.shared.registerProvider { await source.fetch() }
        let initialToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(initialToken, tokenA)

        let store = Store(initialState: companyState(), reducer: KlaviyoReducer())
        _ = store.send(.initialize("A"))

        XCTAssertEqual(store.state.value.apiKey, "A")
        let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        let fetchCount = await source.invocations
        XCTAssertEqual(currentToken, tokenA)
        XCTAssertEqual(fetchCount, 1)
    }

    @MainActor
    func testRapidCompanyChangesUseLatestKeyAndReplayPendingRequest() async throws {
        let tokenA = try makeToken(subject: "A")
        let tokenC = try makeToken(subject: "C")
        let source = CompanyTokenSource(tokenA)
        await AuthTokenManager.shared.registerProvider { await source.fetch() }
        _ = try await AuthTokenManager.shared.currentToken(mode: .background)

        let store = Store(initialState: companyState(), reducer: KlaviyoReducer())
        let pendingEmailApplied = expectation(description: "pending email applied to company C")
        var publishedB = false
        subscription = store.state.dropFirst().sink { state in
            if state.apiKey == "B", state.initalizationState == .initialized {
                publishedB = true
            }
            if state.apiKey == "C", state.email == "c@example.com" {
                pendingEmailApplied.fulfill()
            }
        }
        pendingEmailApplied.assertForOverFulfill = false

        await source.setToken(tokenC)
        _ = store.send(.initialize("B"))
        _ = store.send(.initialize("C"))
        _ = store.send(.setEmail("c@example.com"))

        XCTAssertEqual(store.state.value.apiKey, "A")
        await fulfillment(of: [pendingEmailApplied], timeout: 3)
        XCTAssertFalse(publishedB)
        XCTAssertEqual(store.state.value.apiKey, "C")
        let currentToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(currentToken, tokenC)
    }

    private func companyState() -> KlaviyoState {
        KlaviyoState(
            apiKey: "A",
            anonymousId: "anonymous-A",
            queue: [],
            initalizationState: .initialized
        )
    }

    private func makeToken(subject: String) throws -> String {
        let currentTime = Date().timeIntervalSince1970
        let payload = try JSONSerialization.data(withJSONObject: [
            "sub": subject,
            "iat": currentTime - 60,
            "exp": currentTime + 3600
        ])
        return [Data("{}".utf8), payload, Data(subject.utf8)]
            .map { data in
                data.base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            }
            .joined(separator: ".")
    }
}

private actor CompanyTokenSource {
    private var token: String
    private let holdFirstFetch: Bool
    private var firstFetchStarted: CheckedContinuation<Void, Never>?
    private var firstFetchReleased: CheckedContinuation<Void, Never>?
    private var firstFetchDidStart = false
    private var firstFetchIsReleased = false
    private(set) var invocations = 0

    init(_ token: String, holdFirstFetch: Bool = false) {
        self.token = token
        self.holdFirstFetch = holdFirstFetch
    }

    func fetch() async -> String {
        invocations += 1
        let result = token
        if holdFirstFetch, invocations == 1 {
            firstFetchDidStart = true
            firstFetchStarted?.resume()
            firstFetchStarted = nil
            if !firstFetchIsReleased {
                await withCheckedContinuation { firstFetchReleased = $0 }
            }
        }
        return result
    }

    func setToken(_ token: String) {
        self.token = token
    }

    func waitForFirstFetch() async {
        if firstFetchDidStart { return }
        await withCheckedContinuation { firstFetchStarted = $0 }
    }

    func releaseFirstFetch() {
        firstFetchIsReleased = true
        firstFetchReleased?.resume()
        firstFetchReleased = nil
    }
}
