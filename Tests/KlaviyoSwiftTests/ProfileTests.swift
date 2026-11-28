@testable import KlaviyoCore
@testable import KlaviyoSwift
import AnyCodable
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

    // MARK: - timezone key

    func testTimezoneKey_matchesCustomTimezoneKey() {
        XCTAssertEqual(Profile.ProfileKey.timezone, .custom(customKey: "timezone"))
    }

    func testUpdateProfileWithProperties_timezone_setsLocationTimezone() {
        let profile = Profile.updateProfileWithProperties(
            dict: [.timezone: AnyEncodable("America/New_York")]
        )

        XCTAssertEqual(profile.location?.timezone, "America/New_York")
        XCTAssertNil(profile.properties["timezone"])
    }

    func testUpdateProfileWithProperties_timezone_serializesToLocationTimezone() throws {
        environment = KlaviyoEnvironment.test()
        let profile = Profile.updateProfileWithProperties(
            dict: [
                .timezone: AnyEncodable("America/New_York"),
                .custom(customKey: "plan"): AnyEncodable("gold")
            ]
        )
        let payload = ProfilePayload(profile, anonymousId: "anon-1")

        let data = try KlaviyoEnvironment.encoder.encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attributes = try XCTUnwrap(json["attributes"] as? [String: Any])
        let location = try XCTUnwrap(attributes["location"] as? [String: Any])
        let properties = try XCTUnwrap(attributes["properties"] as? [String: Any])

        XCTAssertEqual(location["timezone"] as? String, "America/New_York")
        XCTAssertNil(properties["timezone"])
        XCTAssertEqual(properties["plan"] as? String, "gold")
    }

    func testUpdateProfileWithProperties_withoutTimezone_fallsBackToDeviceTimezone() {
        environment = KlaviyoEnvironment.test()
        let profile = Profile.updateProfileWithProperties(dict: [.city: AnyEncodable("Boston")])

        XCTAssertEqual(profile.location?.timezone, "EST")
    }
}
