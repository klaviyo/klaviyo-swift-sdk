@testable import KlaviyoSwift
import XCTest

final class ProfileTests: XCTestCase {
    func testHasNonIdentifierData_identifiersOnly_returnsFalse() {
        let profile = Profile(email: "test@example.com", phoneNumber: "+1234567890", externalId: "ext-123")
        XCTAssertFalse(profile.hasNonIdentifierData)
    }

    func testHasNonIdentifierData_emptyProfile_returnsFalse() {
        let profile = Profile()
        XCTAssertFalse(profile.hasNonIdentifierData)
    }

    func testHasNonIdentifierData_withFirstName_returnsTrue() {
        let profile = Profile(email: "test@example.com", firstName: "Jane")
        XCTAssertTrue(profile.hasNonIdentifierData)
    }

    func testHasNonIdentifierData_withLocation_returnsTrue() {
        let profile = Profile(externalId: "ext-123", location: Profile.Location(city: "Boston"))
        XCTAssertTrue(profile.hasNonIdentifierData)
    }

    func testHasNonIdentifierData_withCustomProperties_returnsTrue() {
        let profile = Profile(email: "test@example.com", properties: ["region": "us-east"])
        XCTAssertTrue(profile.hasNonIdentifierData)
    }
}

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
