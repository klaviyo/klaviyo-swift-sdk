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

    func testStartPreviewStoresTheTokenAndRestartsARegisteredSession() {
        var restarts = 0
        store.restartFormsSession = { restarts += 1 }

        XCTAssertTrue(store.startPreview(validPreviewToken))
        XCTAssertTrue(store.startPreview(validPreviewToken))

        XCTAssertEqual(store.token, validPreviewToken)
        XCTAssertEqual(restarts, 2, "Starting the same preview again restarts the session")
    }

    func testStartPreviewWithoutASessionOnlyStoresTheToken() {
        XCTAssertTrue(store.startPreview(validPreviewToken))
        XCTAssertEqual(store.token, validPreviewToken)
    }

    func testMalformedStartPreviewChangesNothing() {
        var restarts = 0
        store.startPreview(validPreviewToken)
        store.restartFormsSession = { restarts += 1 }

        XCTAssertFalse(store.startPreview("not-a-preview-token"))

        XCTAssertEqual(store.token, validPreviewToken)
        XCTAssertEqual(restarts, 0)
    }

    func testEndPreviewClearsAndRestarts() {
        var restarts = 0
        store.startPreview(validPreviewToken)
        store.restartFormsSession = { restarts += 1 }

        store.endPreview()

        XCTAssertNil(store.token)
        XCTAssertEqual(restarts, 1)
    }
}
