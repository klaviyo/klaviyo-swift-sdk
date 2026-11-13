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
        let allowed = [
            "http://example.com",
            "https://example.com",
            "mailto:a@example.com",
            "tel:+15555550100",
            "sms:+15555550100"
        ]
        for string in allowed {
            let parsed = try XCTUnwrap(URL(string: string))
            XCTAssertTrue(parsed.hasAllowedOpenUrlScheme, "\(string) should be allowed")
        }
    }

    func testSchemeCheckIsCaseInsensitive() throws {
        for string in ["HTTPS://example.com", "MailTo:a@example.com"] {
            let parsed = try XCTUnwrap(URL(string: string))
            XCTAssertTrue(parsed.hasAllowedOpenUrlScheme, "\(string) should be allowed")
        }
    }

    func testDisallowedSchemesAreRejected() throws {
        let disallowed = [
            "javascript:alert(1)",
            "file:///etc/hosts",
            "intent://x",
            "geo:0,0",
            "smsto:123",
            "ftp://example.com"
        ]
        for string in disallowed {
            let parsed = try XCTUnwrap(URL(string: string))
            XCTAssertFalse(parsed.hasAllowedOpenUrlScheme, "\(string) must be rejected")
        }
    }

    func testURLWithoutASchemeIsRejected() throws {
        for string in ["example.com/path", "/relative/path"] {
            let parsed = try XCTUnwrap(URL(string: string))
            XCTAssertNil(parsed.scheme)
            XCTAssertFalse(parsed.hasAllowedOpenUrlScheme, "\(string) has no scheme and must be rejected")
        }
    }
}
