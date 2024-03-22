//
//  APIRequestErrorHandlingTests.swift
//  State management tests related to api request error handling.
//
//  Created by Noah Durell on 12/15/22.
//

@testable import KlaviyoSwift
import Foundation
import XCTest

let TIMEOUT_NANOSECONDS: UInt64 = 10_000_000_000 // 10 seconds

@MainActor
class APIRequestErrorHandlingTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }

    // MARK: - http error

    func testSendRequestHttpFailureDequesRequest() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.httpError(500, TEST_RETURN_DATA)) }

        _ = await store.send(.sendRequest)

        await store.receive(.deQueueCompletedResults(request)) {
            $0.flushing = false
            $0.requestsInFlight = []
        }
    }

    func testSendRequestHttpFailureForPhoneNumberResetsStateAndDequesRequest() async throws {
        var initialState = INITIALIZED_TEST_STATE_INVALID_PHONE()
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.httpError(400, TEST_FAILURE_JSON_INVALID_PHONE_NUMBER.data(using: .utf8)!)) }

        _ = await store.send(.sendRequest)

        await store.receive(.resetStateAndDequeue(request, [InvalidField.phone]), timeout: TIMEOUT_NANOSECONDS) {
            $0.phoneNumber = nil
        }

        await store.receive(.deQueueCompletedResults(request), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    func testSendRequestHttpFailureForEmailResetsStateAndDequesRequest() async throws {
        var initialState = INITIALIZED_TEST_STATE_INVALID_EMAIL()
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.httpError(400, TEST_FAILURE_JSON_INVALID_EMAIL.data(using: .utf8)!)) }

        _ = await store.send(.sendRequest)

        await store.receive(.resetStateAndDequeue(request, [InvalidField.email]), timeout: TIMEOUT_NANOSECONDS) {
            $0.email = nil
        }

        await store.receive(.deQueueCompletedResults(request), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - network error

    func testSendRequestFailureIncrementsRetryCount() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "new_token", enablement: .authorized)
        initialState.requestsInFlight = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.networkError(NSError(domain: "foo", code: NSURLErrorCancelled))) }

        _ = await store.send(.sendRequest)

        await store.receive(.requestFailed(request, .retry(1)), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = [request, request2]
            $0.requestsInFlight = []
            $0.retryInfo = .retry(1)
        }
    }

    func testSendRequestFailureWithBackoff() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retryWithBackoff(requestCount: 1, totalRetryCount: 1, currentBackoff: 1)
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "new_token", enablement: .authorized)
        initialState.requestsInFlight = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.networkError(NSError(domain: "foo", code: NSURLErrorCancelled))) }

        _ = await store.send(.sendRequest)

        await store.receive(.requestFailed(request, .retry(2)), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = [request, request2]
            $0.requestsInFlight = []
            $0.retryInfo = .retry(2)
        }
    }

    func testSendRequestMaxRetries() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retry(ErrorHandlingConstants.maxRetries)

        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        var request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "new_token", enablement: .authorized)
        request2.uuid = "foo"
        initialState.requestsInFlight = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.networkError(NSError(domain: "foo", code: NSURLErrorCancelled))) }

        _ = await store.send(.sendRequest)

        await store.receive(.requestFailed(request, .retry(ErrorHandlingConstants.maxRetries + 1)), timeout: TIMEOUT_NANOSECONDS) {
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

        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.internalError("internal error!")) }

        _ = await store.send(.sendRequest)

        await store.receive(.deQueueCompletedResults(request), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - internal request error

    func testSendRequestInternalRequestError() async throws {
        var initialState = INITIALIZED_TEST_STATE()

        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.internalRequestError(KlaviyoAPI.KlaviyoAPIError.internalError("foo"))) }

        _ = await store.send(.sendRequest)

        await store.receive(.deQueueCompletedResults(request), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - unknown error

    func testSendRequestUnknownError() async throws {
        var initialState = INITIALIZED_TEST_STATE()

        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.unknownError(KlaviyoAPI.KlaviyoAPIError.internalError("foo"))) }

        _ = await store.send(.sendRequest)

        await store.receive(.deQueueCompletedResults(request), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - data decoding error

    func testSendRequestDataDecodingError() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.dataEncodingError(request)) }

        _ = await store.send(.sendRequest)

        await store.receive(.deQueueCompletedResults(request), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - invalid data

    func testSendRequestInvalidData() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.invalidData) }

        _ = await store.send(.sendRequest)

        await store.receive(.deQueueCompletedResults(request), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }

    // MARK: - rate limit error

    func testRateLimitErrorWithExistingRetry() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.rateLimitError) }

        _ = await store.send(.sendRequest)

        await store.receive(.requestFailed(request, .retryWithBackoff(requestCount: 1, totalRetryCount: 1, currentBackoff: 0)), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = [request]
            $0.requestsInFlight = []
            $0.retryInfo = .retryWithBackoff(requestCount: 1, totalRetryCount: 1, currentBackoff: 0)
        }
    }

    func testRateLimitErrorWithExistingBackoffRetry() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retryWithBackoff(requestCount: 2, totalRetryCount: 2, currentBackoff: 4)
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.rateLimitError) }

        _ = await store.send(.sendRequest)

        await store.receive(.requestFailed(request, .retryWithBackoff(requestCount: 3, totalRetryCount: 3, currentBackoff: 8)), timeout: TIMEOUT_NANOSECONDS) {
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
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        initialState.requestsInFlight = [request]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        environment.analytics.klaviyoAPI.send = { _, _ in .failure(.missingOrInvalidResponse(nil)) }

        _ = await store.send(.sendRequest)

        await store.receive(.deQueueCompletedResults(request), timeout: TIMEOUT_NANOSECONDS) {
            $0.flushing = false
            $0.queue = []
            $0.requestsInFlight = []
            $0.retryInfo = .retry(0)
        }
    }
}
