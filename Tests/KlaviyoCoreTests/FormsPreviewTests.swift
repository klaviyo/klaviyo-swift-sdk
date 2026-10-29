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
}
