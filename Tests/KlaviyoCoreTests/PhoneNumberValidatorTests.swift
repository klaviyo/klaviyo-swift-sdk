//
//  PhoneNumberValidatorTests.swift
//  KlaviyoCoreTests
//

@testable import KlaviyoCore
import XCTest

final class PhoneNumberValidatorTests: XCTestCase {
    func testAcceptsE164AndCommonFormatting() {
        let valid = [
            "+12345678901",
            "+18005551234",
            "+44 20 7946 0958",
            "+1 (800) 555-1234",
            "+1.800.555.1234",
            "  +12345678901  ",
            "+1234567", // minimum length
            "+123456789012345" // maximum length
        ]
        for number in valid {
            XCTAssertTrue(PhoneNumberValidator.isValid(number), "expected valid: \(number)")
        }
    }

    func testRejectsNumbersWithoutCountryCode() {
        // `21` is the value from MAGE-1384 that the server accepted (200) but dropped.
        let invalid = ["21", "2345678901", "12345678901", "(800) 555-1234", "800-555-1234", "00442079460958"]
        for number in invalid {
            XCTAssertFalse(PhoneNumberValidator.isValid(number), "expected invalid: \(number)")
        }
    }

    func testRejectsMalformedNumbers() {
        let invalid = [
            "", " ", "+", "+1", "+123456", // too short
            "+1234567890123456", // too long
            "abc",
            "+1800FLOWERS", "+1800abc1234", // letters are rejected (the server converts them to digits)
            "1+2345678901", "++12345678901",
            "+1800555é234", "+1800555#234", "+1800555*234",
            "+١٢٣٤٥٦٧٨٩٠١" // non-ASCII digits
        ]
        for number in invalid {
            XCTAssertFalse(PhoneNumberValidator.isValid(number), "expected invalid: \(number)")
        }
    }

    func testWarningDoesNotLeakThePhoneNumber() {
        XCTAssertFalse(PhoneNumberValidator.invalidFormatWarning.contains("+1800"))
    }
}
