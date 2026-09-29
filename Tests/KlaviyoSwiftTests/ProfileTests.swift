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
