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

    // MARK: - networkError (MAGE-1217: transport errors escalate via .retryWithBackoff)

    /// A transport error from a plain `.retry` state must escalate into `.retryWithBackoff`, not
    /// stay a bare `.retry` — this is the regression MAGE-1217 fixes. Backoff is computed from the
    /// formula shared with 429/5xx: `min(2^attempt, 300) + jitter`; `environment.randomInt` is
    /// stubbed to `0` by `KlaviyoEnvironment.test()`, so jitter is 0 here.
    func testNetworkErrorFromRetryStateEscalatesToBackoff() throws {
        let underlyingError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: nil)
        let error = KlaviyoAPIError.networkError(underlyingError)
        let decision = classifyFailure(error: error, retryState: .retry(2))
        XCTAssertEqual(
            decision,
            .retryWithBackoff(
                .retryWithBackoff(requestCount: 3, totalRetryCount: 3, currentBackoff: 4)
            ),
            "attempt 2 failed → 2^2 = 4s backoff (no jitter in test env), requestCount advances to 3"
        )
    }

    /// A transport error that follows an existing `.retryWithBackoff` (e.g. a prior 429/5xx) must
    /// NOT collapse to a bare `.retry` — it keeps escalating in backoff mode so the request never
    /// reverts to the flat flush-tick cadence.
    func testNetworkErrorFromRetryWithBackoffStateKeepsEscalatingBackoff() throws {
        let underlyingError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: nil)
        let error = KlaviyoAPIError.networkError(underlyingError)
        let decision = classifyFailure(
            error: error,
            retryState: .retryWithBackoff(requestCount: 3, totalRetryCount: 5, currentBackoff: 10)
        )
        XCTAssertEqual(
            decision,
            .retryWithBackoff(
                .retryWithBackoff(requestCount: 4, totalRetryCount: 6, currentBackoff: 8)
            ),
            "requestCount 3 failed → 2^3 = 8s backoff; requestCount/totalRetryCount both advance, " +
                "never falls back to .retry"
        )
    }

    /// Successive transport failures escalate 2^1, 2^2, 2^3 ... up to the 300s cap, exactly like
    /// the 429/5xx path — one formula, not two.
    func testNetworkErrorEscalatesUpToCap() throws {
        let underlyingError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: nil)
        let error = KlaviyoAPIError.networkError(underlyingError)

        var retryState: RetryState = .retry(FlushConstants.initialAttempt)
        var backoffs: [Int] = []
        for _ in 0..<10 {
            let decision = classifyFailure(error: error, retryState: retryState)
            guard case let .retryWithBackoff(newState) = decision,
                  case let .retryWithBackoff(_, _, backoff) = newState else {
                return XCTFail("expected .retryWithBackoff, got \(decision)")
            }
            backoffs.append(backoff)
            retryState = newState
        }

        XCTAssertEqual(backoffs, [2, 4, 8, 16, 32, 64, 128, 256, 300, 300],
                       "escalates as 2^attempt (no jitter in test env), capped at 300s")
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
                .retryWithBackoff(requestCount: 3, totalRetryCount: 3, currentBackoff: backOff)
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
                .retryWithBackoff(requestCount: 3, totalRetryCount: 5, currentBackoff: backOff)
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
                .retryWithBackoff(requestCount: 2, totalRetryCount: 2, currentBackoff: backOff)
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
                .retryWithBackoff(requestCount: 2, totalRetryCount: 4, currentBackoff: backOff)
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
