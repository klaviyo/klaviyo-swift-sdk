//
//  APIRequestErrorHandlingTests.swift
//  State management tests related to api request error handling.
//
//  Created by Noah Durell on 12/15/22.
//

@testable import KlaviyoSwift
import Foundation
import XCTest

@MainActor
class APIRequestErrorHandlingTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }

    // MARK: - http error

    func testSendRequestHttpFailureDequesRequest() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let request = try initialState.buildProfileRequest()
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.httpError(500, TEST_RETURN_DATA)) }

        _ = await store.send(.sendRequest)

        await store.receive(.dequeCompletedResults(request)) {
            $0.flushing = false
            $0.requestsInFlight = []
        }
    }

    // MARK: - network error

    func testSendRequestFailureIncrementsRetryCount() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let request = try initialState.buildProfileRequest()
        let request2 = try initialState.buildTokenRequest()
        initialState.requestsInFlight = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.networkError(NSError(domain: "foo", code: NSURLErrorCancelled))) }

        _ = await store.send(.sendRequest)

        await store.receive(.requestFailed(request, .retry(1))) {
            $0.flushing = false
            $0.queue = [request, request2]
            $0.requestsInFlight = []
            $0.retryInfo = .retry(1)
        }
    }

    func testSendRequestFailureWithBackoff() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retryWithBackoff(requestCount: 1, totalRetryCount: 1, currentBackoff: 1)
        let request = try initialState.buildProfileRequest()
        let request2 = try initialState.buildTokenRequest()
        initialState.requestsInFlight = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.networkError(NSError(domain: "foo", code: NSURLErrorCancelled))) }

        _ = await store.send(.sendRequest)

        await store.receive(.requestFailed(request, .retry(2))) {
            $0.flushing = false
            $0.queue = [request, request2]
            $0.requestsInFlight = []
            $0.retryInfo = .retry(2)
        }
    }

    func testSendRequestMaxRetries() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retry(MAX_RETRIES)

        let request = try initialState.buildProfileRequest()
        var request2 = try initialState.buildTokenRequest()
        request2.uuid = "foo"
        initialState.requestsInFlight = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.networkError(NSError(domain: "foo", code: NSURLErrorCancelled))) }

        _ = await store.send(.sendRequest)

        await store.receive(.requestFailed(request, .retry(MAX_RETRIES + 1))) {
            $0.flushing = false
            $0.queue = [request2]
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - internal error

    func testSendRequestInternalError() async throws {
        // NOTE: should really happen but putting this in for possible future cases and test coverage
        var initialState = INITIALIZED_TEST_STATE()

        let request = try initialState.buildProfileRequest()
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.internalError("internal error!")) }

        _ = await store.send(.sendRequest)

        await store.receive(.dequeCompletedResults(request)) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - internal request error

    func testSendRequestInternalRequestError() async throws {
        var initialState = INITIALIZED_TEST_STATE()

        let request = try initialState.buildProfileRequest()
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.internalRequestError(KlaviyoAPI.KlaviyoAPIError.internalError("foo"))) }

        _ = await store.send(.sendRequest)

        await store.receive(.dequeCompletedResults(request), timeout: 60) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - unknown error

    func testSendRequestUnknownError() async throws {
        var initialState = INITIALIZED_TEST_STATE()

        let request = try initialState.buildProfileRequest()
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.unknownError(KlaviyoAPI.KlaviyoAPIError.internalError("foo"))) }

        _ = await store.send(.sendRequest)

        await store.receive(.dequeCompletedResults(request), timeout: 60) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - data decoding error

    func testSendRequestDataDecodingError() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let request = try initialState.buildProfileRequest()
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.dataEncodingError(request)) }

        _ = await store.send(.sendRequest)

        await store.receive(.dequeCompletedResults(request), timeout: 60) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - invalid data

    func testSendRequestInvalidData() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let request = try initialState.buildProfileRequest()
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.invalidData) }

        _ = await store.send(.sendRequest)

        await store.receive(.dequeCompletedResults(request), timeout: 60) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - rate limit error

    func testRateLimitErrorWithExistingRetry() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let request = try initialState.buildProfileRequest()
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.rateLimitError) }

        _ = await store.send(.sendRequest)

        await store.receive(.requestFailed(request, .retryWithBackoff(requestCount: 1, totalRetryCount: 1, currentBackoff: 0)), timeout: 60) {
            $0.flushing = false
            $0.queue = [request]
            $0.requestsInFlight = []
            $0.retryInfo = .retryWithBackoff(requestCount: 1, totalRetryCount: 1, currentBackoff: 0)
        }
    }

    func testRateLimitErrorWithExistingBackoffRetry() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retryWithBackoff(requestCount: 2, totalRetryCount: 2, currentBackoff: 4)
        let request = try initialState.buildProfileRequest()
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.rateLimitError) }

        _ = await store.send(.sendRequest)

        await store.receive(.requestFailed(request, .retryWithBackoff(requestCount: 3, totalRetryCount: 3, currentBackoff: 8)), timeout: 60) {
            $0.flushing = false
            $0.queue = [request]
            $0.requestsInFlight = []
            $0.retryInfo = .retryWithBackoff(requestCount: 3, totalRetryCount: 3, currentBackoff: 8)
        }
    }

    // MARK: - Missing or invalid response

    func testMissingOrInvalidResponse() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retryWithBackoff(requestCount: 2, totalRetryCount: 2, currentBackoff: 4)
        let request = try initialState.buildProfileRequest()
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _ in .failure(.missingOrInvalidResponse(nil)) }

        _ = await store.send(.sendRequest)

        await store.receive(.dequeCompletedResults(request), timeout: 60) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }
}
