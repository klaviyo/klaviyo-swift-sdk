//
//  String+RedactingTokenTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import XCTest

final class StringRedactingTokenTests: XCTestCase {
    func testRedactsPreviewTokenFromFormsPreviewEndedMessage() {
        let message = """
        {"type":"formsPreviewEnded","data":{"reason":"Preview ended","token":"\(validPreviewToken)"}}
        """

        let redacted = message.redactingJSONToken

        XCTAssertFalse(redacted.contains(validPreviewToken))
        XCTAssertTrue(redacted.contains("\"token\":\"<redacted>\""))
        XCTAssertTrue(redacted.contains("\"type\":\"formsPreviewEnded\""))
        XCTAssertTrue(redacted.contains("\"reason\":\"Preview ended\""))
    }

    func testRedactsTokenRegardlessOfWhitespace() {
        let message = "{ \"token\" : \"\(validPreviewToken)\", \"data\":{ \"reason\":\"done\" } }"

        let redacted = message.redactingJSONToken

        XCTAssertFalse(redacted.contains(validPreviewToken))
        XCTAssertTrue(redacted.contains("\"data\":{ \"reason\":\"done\" }"))
    }

    func testLeavesMessageWithoutTokenUnchanged() {
        let message = "{\"type\":\"formsDataLoaded\",\"data\":{\"formId\":\"abc\"}}"

        XCTAssertEqual(message.redactingJSONToken, message)
    }
}
