//
//  FormsPreviewTokenStoreTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import Combine
import XCTest

private let validPreviewToken = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJ0123-_6"
private let otherPreviewToken = "ZYXWVUTSRQPONMLKJIHGFEDCBAzyxwvutsrqponm987"

@MainActor
final class FormsPreviewTokenStoreTests: XCTestCase {
    private var store: FormsPreviewTokenStore!

    override func setUp() async throws {
        try await super.setUp()
        store = FormsPreviewTokenStore()
    }

    func testStoresValidToken() {
        store.setToken(validPreviewToken)
        XCTAssertEqual(store.token, validPreviewToken)
    }

    func testSurroundingWhitespaceIsTrimmed() {
        let padded: [String] = ["\(validPreviewToken)\n", "  \(validPreviewToken) ", "\t\(validPreviewToken)"]
        for token in padded {
            store.clear()
            store.setToken(token)
            XCTAssertEqual(store.token, validPreviewToken)
        }
    }

    func testNilEmptyAndWhitespaceClearTheToken() {
        for clearValue in [nil, "", "   "] as [String?] {
            store.setToken(validPreviewToken)
            store.setToken(clearValue)
            XCTAssertNil(store.token)
        }
    }

    func testMalformedTokensAreDroppedAndClearThePreviousToken() {
        let shortToken = String(validPreviewToken.dropLast())
        let head = String(validPreviewToken.prefix(20))
        let tail = String(validPreviewToken.dropFirst(21))
        let malformed: [String] = [
            shortToken,
            validPreviewToken + "a",
            shortToken + "=",
            String(validPreviewToken.dropLast(2)) + "'>",
            head + " " + tail
        ]
        for token in malformed {
            store.setToken(otherPreviewToken)
            store.setToken(token)
            XCTAssertNil(store.token, "Expected \(token) to be rejected")
        }
    }

    func testPublishesOnlyOnChange() {
        var published: [String?] = []
        let cancellable = store.$token.dropFirst().sink { published.append($0) }
        store.setToken(validPreviewToken)
        store.setToken(validPreviewToken)
        store.clear()
        store.clear()
        cancellable.cancel()
        XCTAssertEqual(published, [validPreviewToken, nil])
    }

    func testApplyConfigurationTokenReplacesStoredToken() {
        store.applyConfigurationToken(validPreviewToken)
        store.applyConfigurationToken(otherPreviewToken)
        XCTAssertEqual(store.token, otherPreviewToken)
    }

    func testApplyConfigurationTokenWithoutTokenKeepsTokenFromSetter() {
        store.setToken(validPreviewToken)
        store.applyConfigurationToken(nil)
        store.applyConfigurationToken("")
        store.applyConfigurationToken("  ")
        XCTAssertEqual(store.token, validPreviewToken)
    }

    func testApplyConfigurationTokenWithInvalidTokenClearsToken() {
        store.setToken(validPreviewToken)
        store.applyConfigurationToken("<script>")
        XCTAssertNil(store.token)
    }

    func testEndBlocksTokenFromConfigurationButNotFromSetter() {
        store.setToken(validPreviewToken)
        store.end()
        XCTAssertNil(store.token)

        store.applyConfigurationToken(validPreviewToken)
        XCTAssertNil(store.token)

        store.applyConfigurationToken(otherPreviewToken)
        XCTAssertEqual(store.token, otherPreviewToken)

        store.setToken(validPreviewToken)
        XCTAssertEqual(store.token, validPreviewToken)
    }
}
