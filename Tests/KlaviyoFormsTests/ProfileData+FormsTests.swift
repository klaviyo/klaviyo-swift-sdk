@testable import KlaviyoForms
import KlaviyoCore
import XCTest

final class ProfileDataFormsTests: XCTestCase {
    func testToHtmlStringWithCompleteData() throws {
        let profileData = ProfileData(
            email: "test@example.com",
            phoneNumber: "+1234567890",
            externalId: "ext-456",
            anonymousId: "anon-123"
        )

        let htmlString = try profileData.toHtmlString()

        XCTAssertFalse(htmlString.isEmpty)
        XCTAssertTrue(htmlString.contains("\"email\":\"test@example.com\""))
        XCTAssertTrue(htmlString.contains("\"anonymous_id\":\"anon-123\""))
        XCTAssertTrue(htmlString.contains("\"phone_number\":\"+1234567890\""))
        XCTAssertTrue(htmlString.contains("\"external_id\":\"ext-456\""))
    }

    func testToHtmlStringWithPartialData_omitsNilFields() throws {
        let profileData = ProfileData(email: "test@example.com", anonymousId: "anon-123")

        let htmlString = try profileData.toHtmlString()

        XCTAssertTrue(htmlString.contains("\"email\":\"test@example.com\""))
        XCTAssertTrue(htmlString.contains("\"anonymous_id\":\"anon-123\""))
        XCTAssertFalse(htmlString.contains("phone_number"))
        XCTAssertFalse(htmlString.contains("external_id"))
    }

    func testToHtmlStringWithEmptyData() throws {
        let profileData = ProfileData(
            email: nil,
            phoneNumber: nil,
            externalId: nil,
            anonymousId: nil
        )

        let htmlString = try profileData.toHtmlString()
        XCTAssertEqual(htmlString, "{}")
    }
}
