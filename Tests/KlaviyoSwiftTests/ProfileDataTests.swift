@testable import KlaviyoSwift
import XCTest

final class ProfileDataTests: XCTestCase {
    func testToHtmlStringWithCompleteData() throws {
        let profileData = ProfileData(
            email: "test@example.com",
            anonymousId: "anon-123",
            phoneNumber: "+1234567890",
            externalId: "ext-456"
        )

        let htmlString = try profileData.toHtmlString()

        XCTAssertFalse(htmlString.isEmpty)
        XCTAssertTrue(htmlString.contains("\"email\":\"test@example.com\""))
        XCTAssertTrue(htmlString.contains("\"anonymous_id\":\"anon-123\""))
        XCTAssertTrue(htmlString.contains("\"phone_number\":\"+1234567890\""))
        XCTAssertTrue(htmlString.contains("\"external_id\":\"ext-456\""))
    }

    func testToHtmlStringWithEmptyData() throws {
        let profileData = ProfileData(
            email: nil,
            anonymousId: nil,
            phoneNumber: nil,
            externalId: nil
        )

        let htmlString = try profileData.toHtmlString()
        XCTAssertEqual(htmlString, "{}")
    }
}
