@testable import KlaviyoCore
import XCTest

final class RequestAttemptInfoTests: XCTestCase {
    func testInitializerSucceedsWithValidParameters() throws {
        let info = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 3)
        XCTAssertEqual(info.attemptNumber, 1)
        XCTAssertEqual(info.maxAttempts, 3)
    }

    func testInitializerThrowsWhenAttemptNumberIsZero() throws {
        XCTAssertThrowsError(try RequestAttemptInfo(attemptNumber: 0, maxAttempts: 3)) { error in
            guard case let .invalidRange(attempt, max) = error as? RequestAttemptInfo.InitializationError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            XCTAssertEqual(attempt, 0)
            XCTAssertEqual(max, 3)
        }
    }

    func testInitializerThrowsWhenAttemptNumberExceedsMax() throws {
        XCTAssertThrowsError(try RequestAttemptInfo(attemptNumber: 4, maxAttempts: 3)) { error in
            guard case let .invalidRange(attempt, max) = error as? RequestAttemptInfo.InitializationError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            XCTAssertEqual(attempt, 4)
            XCTAssertEqual(max, 3)
        }
    }
}
