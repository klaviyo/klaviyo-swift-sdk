//
//  FlushDecisionTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

@testable import KlaviyoCore
import XCTest

final class FlushDecisionTests: XCTestCase {
    // MARK: - httpError

    func testHttpErrorWithInvalidEmailField() throws {
        // A 422 whose JSON body has an /attributes/email source pointer
        // → clearInvalidFieldsAndDequeue([.email])
        let errorJSON = """
        {
            "errors": [{
                "id": "abc",
                "status": 422,
                "code": "invalid",
                "title": "Invalid input.",
                "detail": "Invalid email.",
                "source": { "pointer": "/data/attributes/email" }
            }]
        }
        """.data(using: .utf8)!
        let error = KlaviyoAPIError.httpError(422, errorJSON)
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(decision, .clearInvalidFieldsAndDequeue([.email]))
    }

    func testHttpErrorWithInvalidPhoneField() throws {
        let errorJSON = """
        {
            "errors": [{
                "id": "abc",
                "status": 422,
                "code": "invalid",
                "title": "Invalid input.",
                "detail": "Invalid phone.",
                "source": { "pointer": "/data/attributes/phone_number" }
            }]
        }
        """.data(using: .utf8)!
        let error = KlaviyoAPIError.httpError(422, errorJSON)
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(decision, .clearInvalidFieldsAndDequeue([.phone]))
    }

    func testHttpErrorWithNoFieldPointers() throws {
        // 4xx with no recognized field pointers → dequeue
        let errorJSON = """
        {
            "errors": [{
                "id": "abc",
                "status": 400,
                "code": "invalid",
                "title": "Bad request.",
                "detail": "Something is wrong.",
                "source": { "pointer": "/data/attributes/some_other_field" }
            }]
        }
        """.data(using: .utf8)!
        let error = KlaviyoAPIError.httpError(400, errorJSON)
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(decision, .dequeue)
    }

    func testHttpErrorWithUnparsableBody() throws {
        // malformed JSON body → dequeue
        let badData = "not json".data(using: .utf8)!
        let error = KlaviyoAPIError.httpError(400, badData)
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(decision, .dequeue)
    }

    // MARK: - networkError

    func testNetworkErrorFromRetryState() throws {
        let underlyingError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: nil)
        let error = KlaviyoAPIError.networkError(underlyingError)
        // .retry(count) → .retry(count + 1)
        let decision = classifyFailure(error: error, retryState: .retry(2))
        XCTAssertEqual(decision, .retry(.retry(3)))
    }

    func testNetworkErrorFromRetryWithBackoffState() throws {
        let underlyingError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: nil)
        let error = KlaviyoAPIError.networkError(underlyingError)
        // .retryWithBackoff(requestCount, …) → .retry(requestCount + 1)
        let decision = classifyFailure(
            error: error,
            retryState: .retryWithBackoff(requestCount: 3, totalRetryCount: 5, currentBackoff: 10)
        )
        XCTAssertEqual(decision, .retry(.retry(4)))
    }

    // MARK: - rateLimitError

    func testRateLimitErrorFromRetryState() throws {
        let backOff = 30
        let error = KlaviyoAPIError.rateLimitError(backOff: backOff)
        // .retry(count) → requestCount = count+1, totalCount = count+1
        let decision = classifyFailure(error: error, retryState: .retry(2))
        XCTAssertEqual(
            decision,
            .retryWithBackoff(
                .retryWithBackoff(requestCount: 3, totalRetryCount: 3, currentBackoff: backOff),
                seconds: backOff
            )
        )
    }

    func testRateLimitErrorFromRetryWithBackoffState() throws {
        let backOff = 60
        let error = KlaviyoAPIError.rateLimitError(backOff: backOff)
        // .retryWithBackoff(requestCount, totalCount, _) → requestCount+1, totalCount+1
        let decision = classifyFailure(
            error: error,
            retryState: .retryWithBackoff(requestCount: 2, totalRetryCount: 4, currentBackoff: 30)
        )
        XCTAssertEqual(
            decision,
            .retryWithBackoff(
                .retryWithBackoff(requestCount: 3, totalRetryCount: 5, currentBackoff: backOff),
                seconds: backOff
            )
        )
    }

    // MARK: - serverError

    func testServerErrorFromRetryState() throws {
        let backOff = 15
        let error = KlaviyoAPIError.serverError(statusCode: 500, backOff: backOff)
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(
            decision,
            .retryWithBackoff(
                .retryWithBackoff(requestCount: 2, totalRetryCount: 2, currentBackoff: backOff),
                seconds: backOff
            )
        )
    }

    func testServerErrorFromRetryWithBackoffState() throws {
        let backOff = 20
        let error = KlaviyoAPIError.serverError(statusCode: 503, backOff: backOff)
        let decision = classifyFailure(
            error: error,
            retryState: .retryWithBackoff(requestCount: 1, totalRetryCount: 3, currentBackoff: 10)
        )
        XCTAssertEqual(
            decision,
            .retryWithBackoff(
                .retryWithBackoff(requestCount: 2, totalRetryCount: 4, currentBackoff: backOff),
                seconds: backOff
            )
        )
    }

    // MARK: - non-retryable errors → dequeue

    func testInternalErrorDequeues() throws {
        let error = KlaviyoAPIError.internalError("something broke")
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(decision, .dequeue)
    }

    func testInternalRequestErrorDequeues() throws {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: nil)
        let error = KlaviyoAPIError.internalRequestError(underlyingError)
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(decision, .dequeue)
    }

    func testUnknownErrorDequeues() throws {
        let underlyingError = NSError(domain: "test", code: 2, userInfo: nil)
        let error = KlaviyoAPIError.unknownError(underlyingError)
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(decision, .dequeue)
    }

    func testDataEncodingErrorDequeues() throws {
        let request = KlaviyoRequest(endpoint: .createProfile("apiKey", CreateProfilePayload(data: .test)))
        let error = KlaviyoAPIError.dataEncodingError(request)
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(decision, .dequeue)
    }

    func testInvalidDataDequeues() throws {
        let error = KlaviyoAPIError.invalidData
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(decision, .dequeue)
    }

    func testMissingOrInvalidResponseDequeues() throws {
        let error = KlaviyoAPIError.missingOrInvalidResponse(nil)
        let decision = classifyFailure(error: error, retryState: .retry(1))
        XCTAssertEqual(decision, .dequeue)
    }
}
