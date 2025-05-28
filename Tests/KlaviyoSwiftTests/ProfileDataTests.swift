@testable import KlaviyoSwift
import XCTest

final class ProfileDataTests: XCTestCase {
    func testToHtmlStringWithCompleteData() throws {
        let profileData = ProfileData(
            apiKey: "test-api-key",
            email: "test@example.com",
            anonymousId: "anon-123",
            phoneNumber: "+1234567890",
            externalId: "ext-456"
        )

        let htmlString = try profileData.toHtmlString()

        XCTAssertFalse(htmlString.isEmpty)
        XCTAssertTrue(htmlString.contains("\"apiKey\":\"test-api-key\""))
        XCTAssertTrue(htmlString.contains("\"email\":\"test@example.com\""))
        XCTAssertTrue(htmlString.contains("\"anonymousId\":\"anon-123\""))
        XCTAssertTrue(htmlString.contains("\"phoneNumber\":\"+1234567890\""))
        XCTAssertTrue(htmlString.contains("\"externalId\":\"ext-456\""))
    }

    func testToHtmlStringWithEmptyData() throws {
        let profileData = ProfileData(
            apiKey: nil,
            email: nil,
            anonymousId: nil,
            phoneNumber: nil,
            externalId: nil
        )

        let htmlString = try profileData.toHtmlString()
        XCTAssertEqual(htmlString, "{}")
    }
}
