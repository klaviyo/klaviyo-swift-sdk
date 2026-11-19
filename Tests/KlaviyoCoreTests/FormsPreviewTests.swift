//
//  FormsPreviewTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import XCTest

final class FormsPreviewTests: XCTestCase {
    private let token = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJ0123-_6"

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    func testReadsParameterFromCustomSchemeAndHTTPSLinks() throws {
        XCTAssertEqual(try FormsPreview.previewTokenParameter(in: url("myapp://home?klaviyo-forms-preview=\(token)")), token)
        XCTAssertEqual(try FormsPreview.previewTokenParameter(in: url("myapp:///?klaviyo-forms-preview=\(token)")), token)
        XCTAssertEqual(
            try FormsPreview.previewTokenParameter(in: url("https://shop.example.com/a/b?klaviyo-forms-preview=\(token)")),
            token
        )
    }

    func testReadsParameterAmongOtherParameters() throws {
        let link = try url("https://example.com/p?utm_source=qr&klaviyo-forms-preview=\(token)&x=1")
        XCTAssertEqual(FormsPreview.previewTokenParameter(in: link), token)
    }

    func testReturnsNilWithoutParameter() throws {
        XCTAssertNil(try FormsPreview.previewTokenParameter(in: url("myapp://home")))
        XCTAssertNil(try FormsPreview.previewTokenParameter(in: url("https://example.com/?other=\(token)")))
        XCTAssertNil(try FormsPreview.previewTokenParameter(in: url("https://example.com/#klaviyo-forms-preview=\(token)")))
    }

    func testReturnsRawValueWithoutValidating() throws {
        XCTAssertEqual(try FormsPreview.previewTokenParameter(in: url("myapp://x?klaviyo-forms-preview=short")), "short")
        XCTAssertEqual(try FormsPreview.previewTokenParameter(in: url("myapp://x?klaviyo-forms-preview=")), "")
        XCTAssertEqual(try FormsPreview.previewTokenParameter(in: url("myapp://x?klaviyo-forms-preview")), "")
    }

    func testRemovesParameterAndKeepsTheRestOfTheLink() throws {
        let link = try url("https://example.com/p?utm_source=qr&klaviyo-forms-preview=\(token)&x=1#frag")
        XCTAssertEqual(
            FormsPreview.removingPreviewTokenParameter(from: link).absoluteString,
            "https://example.com/p?utm_source=qr&x=1#frag"
        )
        XCTAssertEqual(
            try FormsPreview.removingPreviewTokenParameter(from: url("myapp://home?klaviyo-forms-preview=\(token)")).absoluteString,
            "myapp://home"
        )
        let untouched = try url("myapp://home?a=1")
        XCTAssertEqual(FormsPreview.removingPreviewTokenParameter(from: untouched), untouched)
    }

    func testStringStripKeepsEveryOtherByte() {
        let siblings = "q=a%2Bb&next=https%3A%2F%2Fexample.com%2F%3Fa%3D1&&empty=&flag"
        XCTAssertEqual(
            FormsPreview.removingPreviewTokenParameter(fromURLString: "myapp://h/p?klaviyo-forms-preview=\(token)&\(siblings)#f"),
            "myapp://h/p?\(siblings)#f"
        )
        XCTAssertEqual(
            FormsPreview.removingPreviewTokenParameter(fromURLString: "myapp://h?\(siblings)&klaviyo-forms-preview=\(token)"),
            "myapp://h?\(siblings)"
        )
        XCTAssertEqual(
            FormsPreview.removingPreviewTokenParameter(fromURLString: "myapp://h?klaviyo-forms-preview=\(token)&klaviyo-forms-preview=x"),
            "myapp://h"
        )
    }

    func testStringStripLeavesUnrelatedTextUntouched() {
        for text in [
            "myapp://h?a=1",
            "myapp://h",
            "myapp://h#klaviyo-forms-preview=\(token)",
            "myapp://h?xklaviyo-forms-preview=1",
            "myapp://h?klaviyo-forms-preview-x=1",
            "not a url?a=%2B"
        ] {
            XCTAssertEqual(FormsPreview.removingPreviewTokenParameter(fromURLString: text), text)
        }
    }

    func testStringStripWorksOnTextThatIsNotAValidURL() {
        XCTAssertEqual(
            FormsPreview.removingPreviewTokenParameter(fromURLString: "ht tp://h?klaviyo-forms-preview=\(token)&x=1"),
            "ht tp://h?x=1"
        )
    }

    func testStringReadDecodesValueAndAgreesWithStrip() {
        XCTAssertEqual(FormsPreview.previewTokenParameter(inURLString: "myapp://h?klaviyo-forms-preview=\(token)&x=1"), token)
        XCTAssertEqual(FormsPreview.previewTokenParameter(inURLString: "myapp://h?klaviyo-forms-preview=a%2Db"), "a-b")
        XCTAssertEqual(FormsPreview.previewTokenParameter(inURLString: "ht tp://h?klaviyo-forms-preview=\(token)"), token)
        XCTAssertEqual(FormsPreview.previewTokenParameter(inURLString: "myapp://h?klaviyo-forms-preview"), "")
        XCTAssertNil(FormsPreview.previewTokenParameter(inURLString: "myapp://h#klaviyo-forms-preview=\(token)"))
        XCTAssertNil(FormsPreview.previewTokenParameter(inURLString: "myapp://h?a=1"))
    }

    func testURLStripKeepsSiblingEncoding() throws {
        let link = try url("myapp://h?q=a%2Bb&klaviyo-forms-preview=\(token)&next=https%3A%2F%2Fx.com%2F")
        XCTAssertEqual(
            FormsPreview.removingPreviewTokenParameter(from: link).absoluteString,
            "myapp://h?q=a%2Bb&next=https%3A%2F%2Fx.com%2F"
        )
    }
}
