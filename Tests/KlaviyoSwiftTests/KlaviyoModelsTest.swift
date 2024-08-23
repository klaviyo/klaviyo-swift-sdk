//
//  KlaviyoModelsTest.swift
//
//
//  Created by Ajay Subramanya on 8/23/24.
//

@testable import KlaviyoSwift
import Foundation
import XCTest

class KlaviyoModelsTest: XCTestCase {
    func testProfileModelConvertsToAPIModel() {
        let profile = Profile(
            email: "walter.white@breakingbad.com",
            phoneNumber: "1800-better-call-saul",
            externalId: "999",
            firstName: "Walter",
            lastName: "White",
            organization: "Walter White Inc.",
            title: "Lead chemist",
            image: "https://www.breakingbad.com/walter.png",
            location: Profile.Location(
                address1: "1 main st",
                city: "Albuquerque",
                country: "USA",
                zip: "42000",
                timezone: "MDT"),
            properties: ["order amount": "a lot of money"])
        let anonymousId = "C10H15N"
        let apiProfile = profile.toAPIModel(anonymousId: anonymousId)

        XCTAssertEqual(apiProfile.attributes.email, profile.email)
        XCTAssertEqual(apiProfile.attributes.phoneNumber, profile.phoneNumber)
        XCTAssertEqual(apiProfile.attributes.externalId, profile.externalId)
        XCTAssertEqual(apiProfile.attributes.firstName, profile.firstName)
        XCTAssertEqual(apiProfile.attributes.lastName, profile.lastName)
        XCTAssertEqual(apiProfile.attributes.organization, profile.organization)
        XCTAssertEqual(apiProfile.attributes.title, profile.title)
        XCTAssertEqual(apiProfile.attributes.image, profile.image)
        XCTAssertEqual(apiProfile.attributes.location?.address1, profile.location?.address1)
        XCTAssertEqual(apiProfile.attributes.location?.city, profile.location?.city)
        XCTAssertEqual(apiProfile.attributes.location?.country, profile.location?.country)
        XCTAssertEqual(apiProfile.attributes.location?.zip, profile.location?.zip)
        XCTAssertEqual(apiProfile.attributes.location?.timezone, profile.location?.timezone)

        let apiProps = apiProfile.attributes.properties.value as! [String: Any]
        let orderAmount = apiProps["order amount"] as! String

        XCTAssertEqual(orderAmount, profile.properties["order amount"] as! String)
        XCTAssertEqual(apiProfile.attributes.anonymousId, anonymousId)
    }

    func testProfileWithNoIdsModelConvertsToAPIModel() {
        let profile = Profile(
            firstName: "Walter",
            lastName: "White")
        let anonymousId = "C10H15N"
        let apiProfile = profile.toAPIModel(
            email: "walter.white@breakingbad.com",
            phoneNumber: "1800-better-call-saul",
            externalId: "999",
            anonymousId: anonymousId)
        XCTAssertNil(profile.email)
        XCTAssertNil(profile.phoneNumber)
        XCTAssertNil(profile.externalId)
        XCTAssertEqual(apiProfile.attributes.email, "walter.white@breakingbad.com")
        XCTAssertEqual(apiProfile.attributes.phoneNumber, "1800-better-call-saul")
        XCTAssertEqual(apiProfile.attributes.externalId, "999")
        XCTAssertEqual(apiProfile.attributes.firstName, profile.firstName)
        XCTAssertEqual(apiProfile.attributes.lastName, profile.lastName)
        XCTAssertEqual(apiProfile.attributes.anonymousId, anonymousId)
    }

    func testEmptyStringIdsConvertToNil() {
        let profile = Profile(
            email: "",
            phoneNumber: "",
            externalId: "",
            firstName: "Walter",
            lastName: "White")
        let anonymousId = "C10H15N"
        let apiProfile = profile.toAPIModel(
            anonymousId: anonymousId)

        XCTAssertNil(apiProfile.attributes.email)
        XCTAssertNil(apiProfile.attributes.phoneNumber)
        XCTAssertNil(apiProfile.attributes.externalId)
        XCTAssertEqual(apiProfile.attributes.firstName, profile.firstName)
        XCTAssertEqual(apiProfile.attributes.lastName, profile.lastName)
        XCTAssertEqual(apiProfile.attributes.anonymousId, anonymousId)
    }
}
