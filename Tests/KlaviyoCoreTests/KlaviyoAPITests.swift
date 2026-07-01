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
        )
        ) { result in
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
        let cloudflareResponse = HTTPURLResponse(url: TEST_URL, statusCode: 522, httpVersion: nil, headerFields: nil)!
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), cloudflareResponse)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(.serverError(statusCode, backOff)):
                XCTAssertEqual(statusCode, 522)
                XCTAssertGreaterThan(backOff, 0)
            default:
                XCTFail("Expected a retryable serverError for a 522 response, got \(result)")
            }
        }
    }

    func testUpperBound5xxIsRetryedAsServerError() async throws {
        // The widened range is inclusive of the entire 5xx space (500–599).
        let response = HTTPURLResponse(url: TEST_URL, statusCode: 599, httpVersion: nil, headerFields: nil)!
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), response)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(.serverError(statusCode, _)):
                XCTAssertEqual(statusCode, 599)
            default:
                XCTFail("Expected a retryable serverError for a 599 response, got \(result)")
            }
        }
    }

    func testClientError4xxIsNotRetried() async throws {
        // 4xx codes (including 403 load-shed and 404) must remain non-retryable httpErrors.
        let response = HTTPURLResponse(url: TEST_URL, statusCode: 404, httpVersion: nil, headerFields: nil)!
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), response)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(.httpError(statusCode, _)):
                XCTAssertEqual(statusCode, 404)
            default:
                XCTFail("Expected a non-retryable httpError for a 404 response, got \(result)")
            }
        }
    }

    func testNotImplemented501IsNotRetried() async throws {
        // 501 (Not Implemented) is a permanent/deterministic error and is excluded from the
        // retryable 5xx set — it must fall through to a non-retryable httpError.
        let response = HTTPURLResponse(url: TEST_URL, statusCode: 501, httpVersion: nil, headerFields: nil)!
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), response)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(.httpError(statusCode, _)):
                XCTAssertEqual(statusCode, 501)
            default:
                XCTFail("Expected a non-retryable httpError for a 501 response, got \(result)")
            }
        }
    }

    func testHTTPVersionNotSupported505IsNotRetried() async throws {
        // 505 (HTTP Version Not Supported) is a permanent/deterministic error and is excluded
        // from the retryable 5xx set — it must fall through to a non-retryable httpError.
        let response = HTTPURLResponse(url: TEST_URL, statusCode: 505, httpVersion: nil, headerFields: nil)!
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), response)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(.httpError(statusCode, _)):
                XCTAssertEqual(statusCode, 505)
            default:
                XCTFail("Expected a non-retryable httpError for a 505 response, got \(result)")
            }
        }
    }

    func testLowerBound499IsNotRetried() async throws {
        // 499 sits just below the 5xx range and must remain a non-retryable httpError.
        let response = HTTPURLResponse(url: TEST_URL, statusCode: 499, httpVersion: nil, headerFields: nil)!
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), response)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(.httpError(statusCode, _)):
                XCTAssertEqual(statusCode, 499)
            default:
                XCTFail("Expected a non-retryable httpError for a 499 response, got \(result)")
            }
        }
    }

    func testUpperBound600IsNotRetried() async throws {
        // 600 sits just above the 5xx range and must remain a non-retryable httpError.
        let response = HTTPURLResponse(url: TEST_URL, statusCode: 600, httpVersion: nil, headerFields: nil)!
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), response)
        }) }
        let request = KlaviyoRequest(endpoint: .createProfile("foo", CreateProfilePayload(data: .test)))
        try await sendAndAssert(with: request) { result in
            switch result {
            case let .failure(.httpError(statusCode, _)):
                XCTAssertEqual(statusCode, 600)
            default:
                XCTFail("Expected a non-retryable httpError for a 600 response, got \(result)")
            }
        }
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

    func sendAndAssert(with request: KlaviyoRequest,
                       assertion: (Result<Data, KlaviyoAPIError>) -> Void) async throws {
        let attemptInfo = try XCTUnwrap(RequestAttemptInfo(attemptNumber: 1, maxAttempts: 50))
        let result = await KlaviyoAPI().send(request, attemptInfo)
        assertion(result)
    }
}
