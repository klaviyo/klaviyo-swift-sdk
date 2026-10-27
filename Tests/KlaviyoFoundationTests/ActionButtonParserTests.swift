//
//  ActionButtonParserTests.swift
//  klaviyo-swift-sdk
//

import KlaviyoFoundation
import XCTest

final class ActionButtonParserTests: XCTestCase {
    private func parse(_ buttons: Any, onSkip: (String) -> Void = { _ in }) -> [ActionButton] {
        ActionButtonParser.parse(userInfo: ["body": ["action_buttons": buttons]], onSkip: onSkip)
    }

    private func button(
        id: String? = "id", label: String? = "Label", action: String? = "open_app", url: String? = nil
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        result["id"] = id
        result["label"] = label
        result["action"] = action
        result["url"] = url
        return result
    }

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    // MARK: - Valid buttons

    func testParsesEachActionTypeInPayloadOrder() throws {
        let buttons = parse([
            button(id: "1", label: "Shop", action: "deep_link", url: "myapp://sale"),
            button(id: "2", label: "Open", action: "open_app"),
            button(id: "3", label: "Web", action: "open_url", url: "https://example.com/sale")
        ])
        XCTAssertEqual(buttons, [
            try ActionButton(id: "1", label: "Shop", destination: .deepLink(url("myapp://sale"))),
            ActionButton(id: "2", label: "Open", destination: .openApp),
            try ActionButton(id: "3", label: "Web", destination: .openUrl(url("https://example.com/sale")))
        ])
    }

    func testDestinationReportsItsActionType() throws {
        XCTAssertEqual(ActionButtonDestination.openApp.type, .openApp)
        XCTAssertEqual(try ActionButtonDestination.deepLink(url("myapp://x")).type, .deepLink)
        XCTAssertEqual(try ActionButtonDestination.openUrl(url("https://x.com")).type, .openUrl)
    }

    func testDeepLinkAcceptsAnyScheme() {
        XCTAssertEqual(parse([button(action: "deep_link", url: "https://www.google.com")]).count, 1)
    }

    func testOpenUrlAcceptsEveryAllowedScheme() {
        for scheme in ["https://example.com", "http://example.com", "mailto:a@b.com", "tel:123", "sms:123"] {
            XCTAssertEqual(parse([button(action: "open_url", url: scheme)]).count, 1, "\(scheme) must be kept")
        }
    }

    func testNullUrlIsTreatedAsAbsent() {
        XCTAssertEqual(parse([["id": "a", "label": "x", "action": "open_app", "url": NSNull()]]).count, 1)
    }

    func testAcceptsNestedDictionariesThatAreNotStringKeyed() {
        let entry: [AnyHashable: Any] = ["id": "a", "label": "x", "action": "open_app"]
        let userInfo: [AnyHashable: Any] = ["body": NSDictionary(dictionary: ["action_buttons": [entry]])]
        XCTAssertEqual(ActionButtonParser.parse(userInfo: userInfo).map(\.id), ["a"])
    }

    func testDestinationInitAppliesTheSameRulesToAnyCaller() throws {
        XCTAssertEqual(ActionButtonDestination(action: .openApp, url: nil), .openApp)
        XCTAssertNil(ActionButtonDestination(action: .openApp, url: "myapp://x"))
        XCTAssertEqual(ActionButtonDestination(action: .deepLink, url: "myapp://x"), try .deepLink(url("myapp://x")))
        XCTAssertNil(ActionButtonDestination(action: .deepLink, url: nil))
        XCTAssertEqual(ActionButtonDestination(action: .openUrl, url: "https://x.com"), try .openUrl(url("https://x.com")))
        XCTAssertNil(ActionButtonDestination(action: .openUrl, url: "myapp://x"))
        XCTAssertNil(ActionButtonDestination(action: .openUrl, url: nil))
    }

    /// The Mobile Inbox persists this encoding, so it must not change by accident.
    func testEncodedShapeIsStable() throws {
        let button = try ActionButton(id: "a", label: "A", destination: .deepLink(url("myapp://x")))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(
            try String(decoding: encoder.encode(button), as: UTF8.self),
            #"{"destination":{"deepLink":{"_0":"myapp:\/\/x"}},"id":"a","label":"A"}"#
        )
        XCTAssertEqual(try JSONDecoder().decode(ActionButton.self, from: encoder.encode(button)), button)
    }

    // MARK: - Skipped buttons

    func testSkipsButtonsMissingARequiredField() {
        for invalid in [button(id: nil), button(label: nil), button(action: nil), button(action: "unknown")] {
            XCTAssertTrue(parse([invalid]).isEmpty, "\(invalid) must be skipped")
        }
    }

    func testSkipsButtonsWithEmptyIdOrLabel() {
        XCTAssertTrue(parse([button(id: "")]).isEmpty)
        XCTAssertTrue(parse([button(label: "")]).isEmpty)
    }

    func testSkipsOpenAppWithUrl() {
        XCTAssertTrue(parse([button(action: "open_app", url: "myapp://nope")]).isEmpty)
        XCTAssertTrue(parse([button(action: "open_app", url: "")]).isEmpty, "an empty url is still a url")
    }

    func testSkipsAnyButtonWhoseUrlIsNotAString() {
        for action in ["open_app", "deep_link", "open_url"] {
            for url: Any in [123, true, ["a": "b"], ["https://example.com"]] {
                let entry: [String: Any] = ["id": "a", "label": "x", "action": action, "url": url]
                XCTAssertTrue(parse([entry]).isEmpty, "\(action) with url \(url) must be skipped")
            }
        }
    }

    func testSkipsDeepLinkAndOpenUrlWithoutUrl() {
        XCTAssertTrue(parse([button(action: "deep_link")]).isEmpty)
        XCTAssertTrue(parse([button(action: "open_url")]).isEmpty)
    }

    func testSkipsOpenUrlWithSchemeOutsideTheAllowlist() {
        for blocked in ["javascript:alert(1)", "intent://scan#Intent;end", "smsto:123", "file:///etc/hosts",
                        "myapp://deep", "example.com"] {
            XCTAssertTrue(parse([button(action: "open_url", url: blocked)]).isEmpty, "\(blocked) must be skipped")
        }
    }

    func testMalformedEntriesDoNotDropTheirNeighbours() {
        let buttons = parse(["not a dictionary", NSNull(), button(id: nil), button(id: "ok")])
        XCTAssertEqual(buttons.map(\.id), ["ok"])
    }

    func testReportsEachSkippedButton() {
        var reasons: [String] = []
        _ = parse(["oops", button(id: nil), button(action: "open_app", url: "myapp://x"), button(id: "ok")]) {
            reasons.append($0)
        }
        XCTAssertEqual(reasons.count, 3)
    }

    // MARK: - Missing or malformed containers

    func testMissingOrNonArrayActionButtonsMeansNoButtons() {
        XCTAssertTrue(ActionButtonParser.parse(userInfo: [:]).isEmpty)
        XCTAssertTrue(ActionButtonParser.parse(userInfo: ["body": "oops"]).isEmpty)
        XCTAssertTrue(ActionButtonParser.parse(userInfo: ["body": [String: Any]()]).isEmpty)
        XCTAssertTrue(parse("oops").isEmpty)
        XCTAssertTrue(parse([Any]()).isEmpty)
    }
}
