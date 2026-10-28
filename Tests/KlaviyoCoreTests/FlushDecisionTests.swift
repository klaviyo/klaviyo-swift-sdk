//
//  FlushDecisionTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

@testable import KlaviyoCore
import XCTest

final class FlushDecisionTests: XCTestCase {
    // `classifyFailure`'s .networkError branch now computes a jittered backoff via
    // `environment.randomInt`. Pin the global `environment` to the deterministic test double
    // (`randomInt: { 0 }`) for this class so assertions aren't at the mercy of whichever value a
    // previously-run test class left behind, and restore it afterward so later classes aren't
    // affected by this one.
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
    }

    override func tearDown() {
        environment = KlaviyoEnvironment.test()
        super.tearDown()
    }

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
        let decision = classifyFailure(error: error, attemptNumber: 1)
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
        let decision = classifyFailure(error: error, attemptNumber: 1)
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
        let decision = classifyFailure(error: error, attemptNumber: 1)
        XCTAssertEqual(decision, .dequeue)
    }

    func testHttpErrorWithUnparsableBody() throws {
        // malformed JSON body → dequeue
        let badData = "not json".data(using: .utf8)!
        let error = KlaviyoAPIError.httpError(400, badData)
        let decision = classifyFailure(error: error, attemptNumber: 1)
        XCTAssertEqual(decision, .dequeue)
    }

    // MARK: - networkError (transport errors back off like 429/5xx)

    /// A transport error backs off with the formula shared with 429/5xx: `min(2^attempt, 300) +
    /// jitter`, keyed on the failing request's own attempt. Jitter is `0` in `KlaviyoEnvironment.test()`.
    func testNetworkErrorBacksOffFromItsOwnAttempt() {
        let error = KlaviyoAPIError.networkError(URLError(.notConnectedToInternet))
        XCTAssertEqual(classifyFailure(error: error, attemptNumber: 2), .retry(backoff: 4),
                       "attempt 2 failed → 2^2 = 4s backoff")
    }

    /// Successive transport failures escalate 2^1, 2^2, 2^3 ... up to the 300s cap, exactly like
    /// the 429/5xx path — one formula, not two.
    func testNetworkErrorEscalatesUpToCap() throws {
        let error = KlaviyoAPIError.networkError(URLError(.notConnectedToInternet))
        let backoffs = (1...10).map { attempt -> Int? in
            guard case let .retry(backoff) = classifyFailure(error: error, attemptNumber: attempt) else {
                return nil
            }
            return backoff
        }
        XCTAssertEqual(backoffs, [2, 4, 8, 16, 32, 64, 128, 256, 300, 300],
                       "escalates as 2^attempt (no jitter in test env), capped at 300s")
    }

    // MARK: - rateLimitError / serverError

    /// `KlaviyoAPI` already folded Retry-After + jitter into the error's backoff; it passes through
    /// unchanged regardless of attempt number.
    func testRateLimitErrorUsesProvidedBackoff() {
        let error = KlaviyoAPIError.rateLimitError(backOff: 30)
        XCTAssertEqual(classifyFailure(error: error, attemptNumber: 3), .retry(backoff: 30))
    }

    func testServerErrorUsesProvidedBackoff() {
        let error = KlaviyoAPIError.serverError(statusCode: 503, backOff: 15)
        XCTAssertEqual(classifyFailure(error: error, attemptNumber: 1), .retry(backoff: 15))
    }

    // MARK: - non-retryable errors → dequeue

    func testInternalErrorDequeues() throws {
        let error = KlaviyoAPIError.internalError("something broke")
        let decision = classifyFailure(error: error, attemptNumber: 1)
        XCTAssertEqual(decision, .dequeue)
    }

    func testInternalRequestErrorDequeues() throws {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: nil)
        let error = KlaviyoAPIError.internalRequestError(underlyingError)
        let decision = classifyFailure(error: error, attemptNumber: 1)
        XCTAssertEqual(decision, .dequeue)
    }

    func testUnknownErrorDequeues() throws {
        let underlyingError = NSError(domain: "test", code: 2, userInfo: nil)
        let error = KlaviyoAPIError.unknownError(underlyingError)
        let decision = classifyFailure(error: error, attemptNumber: 1)
        XCTAssertEqual(decision, .dequeue)
    }

    func testDataEncodingErrorDequeues() throws {
        let request = KlaviyoRequest(endpoint: .createProfile("apiKey", CreateProfilePayload(data: .test)))
        let error = KlaviyoAPIError.dataEncodingError(request)
        let decision = classifyFailure(error: error, attemptNumber: 1)
        XCTAssertEqual(decision, .dequeue)
    }

    func testInvalidDataDequeues() throws {
        let error = KlaviyoAPIError.invalidData
        let decision = classifyFailure(error: error, attemptNumber: 1)
        XCTAssertEqual(decision, .dequeue)
    }

    func testMissingOrInvalidResponseDequeues() throws {
        let error = KlaviyoAPIError.missingOrInvalidResponse(nil)
        let decision = classifyFailure(error: error, attemptNumber: 1)
        XCTAssertEqual(decision, .dequeue)
    }
}
