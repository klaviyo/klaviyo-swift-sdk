//
//  URLSchemeAllowlistTests.swift
//  klaviyo-swift-sdk
//

import KlaviyoFoundation
import XCTest

final class URLSchemeAllowlistTests: XCTestCase {
    func testAllowedSchemesAreExactlyTheDocumentedSet() {
        XCTAssertEqual(openUrlAllowedSchemes, ["http", "https", "mailto", "tel", "sms"])
    }

    func testAllowedURLsPass() throws {
        for string in [
            "http://example.com", "https://example.com", "mailto:a@example.com", "tel:+15555550100", "sms:+15555550100"
        ] {
            XCTAssertTrue(try XCTUnwrap(URL(string: string)).hasAllowedOpenUrlScheme, "\(string) should be allowed")
        }
    }

    func testSchemeCheckIsCaseInsensitive() throws {
        XCTAssertTrue(try XCTUnwrap(URL(string: "HTTPS://example.com")).hasAllowedOpenUrlScheme)
        XCTAssertTrue(try XCTUnwrap(URL(string: "MailTo:a@example.com")).hasAllowedOpenUrlScheme)
    }

    func testDisallowedSchemesAreRejected() throws {
        for string in [
            "javascript:alert(1)", "file:///etc/hosts", "intent://x", "geo:0,0", "smsto:123", "ftp://example.com"
        ] {
            XCTAssertFalse(try XCTUnwrap(URL(string: string)).hasAllowedOpenUrlScheme, "\(string) must be rejected")
        }
    }

    func testURLWithoutASchemeIsRejected() throws {
        for string in ["example.com/path", "/relative/path"] {
            let url = try XCTUnwrap(URL(string: string))
            XCTAssertNil(url.scheme)
            XCTAssertFalse(url.hasAllowedOpenUrlScheme, "\(string) has no scheme and must be rejected")
        }
    }
}
