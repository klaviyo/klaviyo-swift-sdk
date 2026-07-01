//
//  KlaviyoAPITests.swift
//
//
//  Created by Noah Durell on 11/16/22.
//

import KlaviyoCore
import SnapshotTesting
import XCTest

@MainActor
final class KlaviyoAPITests: XCTestCase {
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
    }

    func testInvalidURL() async throws {
        environment.apiURL = { URLComponents() }

        try await sendAndAssert(with: KlaviyoRequest(
            endpoint: .createProfile("foo", CreateProfilePayload(data: .test))
        )) { result in
            switch result {
            case let .failure(error):
                assertSnapshot(matching: error, as: .description)
            default:
                XCTFail("Expected url failure")
            }
        }
    }

    func testEncodingError() async throws {
        environment.encodeJSON = { _ in throw EncodingError.invalidValue("foo", .init(codingPath: [], debugDescription: "invalid"))
        }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected encoding error.")
            }
        }
    }

    func testNetworkError() async throws {
        environment.networkSession = { NetworkSession.test(data: { _ in
            throw NSError(domain: "network error", code: 0)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testInvalidStatusCode() async throws {
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), .non200Response)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testCloudflare5xxIsRetryedAsServerError() async throws {
        // Cloudflare edge codes (520–527) sit outside the legacy {500,502,503,504} allowlist.
        // They must now be classified as retryable server errors.
        try await assertServerErrorRetried(522)
    }

    func testUpperBound5xxIsRetryedAsServerError() async throws {
        // The widened range is inclusive of the entire 5xx space (500–599).
        try await assertServerErrorRetried(599)
    }

    func testClientError4xxIsNotRetried() async throws {
        // 4xx codes (including 403 load-shed and 404) must remain non-retryable httpErrors.
        try await assertNotRetried(404)
    }

    func testNotImplemented501IsRetriedAsServerError() async throws {
        // 501 (Not Implemented) is in-range and deliberately retried: for the SDK's fixed request
        // shapes a genuine origin 501 is effectively unreachable, so any 501 we see is edge/CDN
        // noise during an incident — exactly what we want to retry.
        try await assertServerErrorRetried(501)
    }

    func testHTTPVersionNotSupported505IsRetriedAsServerError() async throws {
        // 505 (HTTP Version Not Supported) is in-range and deliberately retried for the same
        // reason as 501: a genuine origin 505 is effectively unreachable for the SDK's fixed
        // request shapes, so any 505 we see is edge/CDN noise during an incident.
        try await assertServerErrorRetried(505)
    }

    func testLowerBound499IsNotRetried() async throws {
        // 499 sits just below the 5xx range and must remain a non-retryable httpError.
        try await assertNotRetried(499)
    }

    func testUpperBound600IsNotRetried() async throws {
        // 600 sits just above the 5xx range and must remain a non-retryable httpError.
        try await assertNotRetried(600)
    }

    func testSuccessfulResponseWithProfile() async throws {
        environment.networkSession = { NetworkSession.test(data: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://dead_beef/client/profiles/?company_id=foo")
            XCTAssertEqual(request.allHTTPHeaderFields?["X-Klaviyo-Attempt-Count"], "1/50")
            return (Data(), .validResponse)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .success(data):
                XCTAssertEqual(data.count, 0)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testSuccessfulResponseWithEvent() async throws {
        environment.networkSession = { NetworkSession.test(data: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://dead_beef/client/events/?company_id=foo")
            XCTAssertEqual(request.allHTTPHeaderFields?["X-Klaviyo-Attempt-Count"], "1/50")
            return (Data(), .validResponse)
        }) }
        let request = KlaviyoRequest(endpoint: .createEvent("foo", CreateEventPayload(data: CreateEventPayload.Event(name: "test"))))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .success(data):
                XCTAssertEqual(data.count, 0)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testSuccessfulResponseWithStoreToken() async throws {
        environment.networkSession = { NetworkSession.test(data: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://dead_beef/client/push-tokens/?company_id=foo")
            XCTAssertEqual(request.allHTTPHeaderFields?["X-Klaviyo-Attempt-Count"], "1/50")
            return (Data(), .validResponse)
        }) }
        let request = KlaviyoRequest(endpoint: .registerPushToken("foo", .test))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .success(data):
                XCTAssertEqual(data.count, 0)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testRateLimitUsesRetryAfterWhenGreaterThanBackoff() async throws {
        // attemptNumber 1 => exponential backoff = 2^1 = 2s; Retry-After 60s wins. Jitter is 0 in tests.
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), Self.retryableResponse(statusCode: 429, retryAfter: "60"))
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        let attemptInfo = try XCTUnwrap(RequestAttemptInfo(attemptNumber: 1, maxAttempts: 50))

        let result = await KlaviyoAPI().send(request, attemptInfo)

        guard case let .failure(.rateLimitError(backOff)) = result else {
            XCTFail("Expected rateLimitError, got \(result)")
            return
        }
        XCTAssertEqual(backOff, 60)
    }

    func testRateLimitUsesBackoffWhenGreaterThanRetryAfter() async throws {
        // attemptNumber 6 => exponential backoff = 2^6 = 64s; Retry-After 10s, so backoff wins.
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), Self.retryableResponse(statusCode: 429, retryAfter: "10"))
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        let attemptInfo = try XCTUnwrap(RequestAttemptInfo(attemptNumber: 6, maxAttempts: 50))

        let result = await KlaviyoAPI().send(request, attemptInfo)

        guard case let .failure(.rateLimitError(backOff)) = result else {
            XCTFail("Expected rateLimitError, got \(result)")
            return
        }
        XCTAssertEqual(backOff, 64)
    }

    func testServerErrorUsesGreaterOfRetryAfterAndBackoff() async throws {
        // 503 with Retry-After 30s vs attemptNumber 1 backoff (2s) => Retry-After wins.
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), Self.retryableResponse(statusCode: 503, retryAfter: "30"))
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        let attemptInfo = try XCTUnwrap(RequestAttemptInfo(attemptNumber: 1, maxAttempts: 50))

        let result = await KlaviyoAPI().send(request, attemptInfo)

        guard case let .failure(.serverError(statusCode, backOff)) = result else {
            XCTFail("Expected serverError, got \(result)")
            return
        }
        XCTAssertEqual(statusCode, 503)
        XCTAssertEqual(backOff, 30)
    }

    func testRetryableErrorFallsBackToBackoffWhenNoRetryAfter() async throws {
        // No Retry-After header => use exponential backoff (2^3 = 8s).
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), Self.retryableResponse(statusCode: 429, retryAfter: nil))
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        let attemptInfo = try XCTUnwrap(RequestAttemptInfo(attemptNumber: 3, maxAttempts: 50))

        let result = await KlaviyoAPI().send(request, attemptInfo)

        guard case let .failure(.rateLimitError(backOff)) = result else {
            XCTFail("Expected rateLimitError, got \(result)")
            return
        }
        XCTAssertEqual(backOff, 8)
    }

    func testExponentialBackoffCappedAtMaxRetryInterval() async throws {
        // attemptNumber 9 => 2^9 = 512s, which exceeds the 300s cap; no Retry-After. Jitter is 0.
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), Self.retryableResponse(statusCode: 429, retryAfter: nil))
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        let attemptInfo = try XCTUnwrap(RequestAttemptInfo(attemptNumber: 9, maxAttempts: 50))

        let result = await KlaviyoAPI().send(request, attemptInfo)

        guard case let .failure(.rateLimitError(backOff)) = result else {
            XCTFail("Expected rateLimitError, got \(result)")
            return
        }
        XCTAssertEqual(backOff, 300)
    }

    func testLargeRetryAfterExceedsBackoffCap() async throws {
        // A server Retry-After (600s) larger than the 300s cap is still honored; only our own
        // exponential backoff is capped. attemptNumber 9 => capped exp 300s, so Retry-After wins.
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), Self.retryableResponse(statusCode: 429, retryAfter: "600"))
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        let attemptInfo = try XCTUnwrap(RequestAttemptInfo(attemptNumber: 9, maxAttempts: 50))

        let result = await KlaviyoAPI().send(request, attemptInfo)

        guard case let .failure(.rateLimitError(backOff)) = result else {
            XCTFail("Expected rateLimitError, got \(result)")
            return
        }
        XCTAssertEqual(backOff, 600)
    }

    func testRetryableErrorFallsBackToBackoffWhenRetryAfterUnparseable() async throws {
        // Present-but-unparseable Retry-After (e.g. an HTTP-date) => use exponential backoff (2^3 = 8s).
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), Self.retryableResponse(statusCode: 429, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT"))
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        let attemptInfo = try XCTUnwrap(RequestAttemptInfo(attemptNumber: 3, maxAttempts: 50))

        let result = await KlaviyoAPI().send(request, attemptInfo)

        guard case let .failure(.rateLimitError(backOff)) = result else {
            XCTFail("Expected rateLimitError, got \(result)")
            return
        }
        XCTAssertEqual(backOff, 8)
    }

    private static func retryableResponse(statusCode: Int, retryAfter: String?) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let retryAfter {
            headers[RetryBackoffConstants.retryAfterHeader] = retryAfter
        }
        return HTTPURLResponse(
            url: TEST_URL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    func sendAndAssert(with request: KlaviyoRequest,
                       assertion: (Result<Data, KlaviyoAPIError>) -> Void) async throws {
        let attemptInfo = try XCTUnwrap(RequestAttemptInfo(attemptNumber: 1, maxAttempts: 50))
        let result = await KlaviyoAPI().send(request, attemptInfo)
        assertion(result)
    }

    /// Stubs the network session to return `code` and asserts the request maps to a
    /// retryable `.serverError` carrying that status code and a positive back-off.
    func assertServerErrorRetried(_ code: Int,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) async throws {
        let response = HTTPURLResponse(url: TEST_URL, statusCode: code, httpVersion: nil, headerFields: nil)!
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), response)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(.serverError(statusCode, backOff)):
                XCTAssertEqual(statusCode, code, file: file, line: line)
                XCTAssertGreaterThan(backOff, 0, file: file, line: line)
            default:
                XCTFail(
                    "Expected a retryable serverError for a \(code) response, got \(result)",
                    file: file, line: line
                )
            }
        }
    }

    /// Stubs the network session to return `code` and asserts the request maps to a
    /// non-retryable `.httpError` carrying that status code.
    func assertNotRetried(_ code: Int,
                          file: StaticString = #filePath,
                          line: UInt = #line) async throws {
        let response = HTTPURLResponse(url: TEST_URL, statusCode: code, httpVersion: nil, headerFields: nil)!
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), response)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(.httpError(statusCode, _)):
                XCTAssertEqual(statusCode, code, file: file, line: line)
            default:
                XCTFail(
                    "Expected a non-retryable httpError for a \(code) response, got \(result)",
                    file: file, line: line
                )
            }
        }
    }
}
