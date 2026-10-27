//
//  KlaviyoActionButtonParserTests.swift
//
//
//  Created by Belle Lim on 1/20/26.
//

@testable import KlaviyoSwiftExtension
import Foundation
import KlaviyoFoundation
import UserNotifications
import XCTest

/// Which buttons are valid is covered by `ActionButtonParserTests` in `KlaviyoFoundationTests`.
/// These tests cover what this wrapper adds.
class KlaviyoActionButtonParserTests: XCTestCase {
    private func userInfo(_ buttons: [[String: Any]]) -> [AnyHashable: Any] {
        ["body": ["_k": [String: Any](), "action_buttons": buttons]]
    }

    func testParseActionButtons_ReturnsOnlyTheValidButtons() {
        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo([
            ["label": "Missing id", "action": "deep_link", "url": "myapp://sale"],
            ["id": "com.klaviyo.test.valid", "label": "Valid", "action": "deep_link", "url": "myapp://valid"]
        ]))

        XCTAssertEqual(result?.map(\.id), ["com.klaviyo.test.valid"])
    }

    func testParseActionButtons_ReturnsNilWhenAllButtonsInvalid() {
        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo([
            ["label": "Missing id", "action": "deep_link"],
            ["id": "com.klaviyo.test.missing_label"]
        ]))

        XCTAssertNil(result, "Should return nil when all buttons are invalid")
    }

    func testParseActionButtons_ReturnsNilWhenThereAreNoButtons() {
        XCTAssertNil(KlaviyoActionButtonParser.parseActionButtons(from: [:]))
        XCTAssertNil(KlaviyoActionButtonParser.parseActionButtons(from: userInfo([])))
    }

    func testCreateActions_BuildsForegroundActionsFromEachButton() throws {
        let buttons = try XCTUnwrap(KlaviyoActionButtonParser.parseActionButtons(from: userInfo([
            ["id": "one", "label": "Button One", "action": "deep_link", "url": "myapp://one"],
            ["id": "two", "label": "Button Two", "action": "open_app"]
        ])))

        let actions = KlaviyoActionButtonParser.createActions(from: buttons)

        XCTAssertEqual(actions.map(\.identifier), ["one", "two"])
        XCTAssertEqual(actions.map(\.title), ["Button One", "Button Two"])
        XCTAssertTrue(actions.allSatisfy { $0.options.contains(.foreground) })
    }
}
