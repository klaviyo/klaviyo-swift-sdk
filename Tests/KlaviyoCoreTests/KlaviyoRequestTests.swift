@testable import KlaviyoCore
import XCTest

final class KlaviyoRequestTests: XCTestCase {
    func testURLRequestSetsAttemptHeader() throws {
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(.test))
        let attemptInfo = try RequestAttemptInfo(attemptNumber: 3, maxAttempts: 7)
        let urlRequest = try request.urlRequest(attemptInfo: attemptInfo)
        let header = urlRequest.value(forHTTPHeaderField: "X-Klaviyo-Attempt-Count")
        XCTAssertEqual(header, "3/7")
    }
}
