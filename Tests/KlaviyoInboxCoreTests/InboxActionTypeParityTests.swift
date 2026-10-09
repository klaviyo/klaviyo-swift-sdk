//
//  InboxActionTypeParityTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import KlaviyoCore
import KlaviyoInboxCore
import XCTest

/// `InboxActionType` and `InboxURLSchemeAllowlist` duplicate `KlaviyoCore.ActionType` and
/// `openUrlAllowedSchemes` because `KlaviyoInboxCore` cannot depend on `KlaviyoCore` (extension-safe).
/// MAGE-1372 consolidates them; until then these tests fail if the copies drift.
final class InboxActionTypeParityTests: XCTestCase {
    /// Exhaustive on purpose: adding a case to `KlaviyoCore.ActionType` fails to compile here,
    /// which is the prompt to mirror it into `InboxActionType`.
    private func raw(_ type: KlaviyoCore.ActionType) -> String {
        switch type {
        case .openApp: return InboxActionType.openApp.rawValue
        case .deepLink: return InboxActionType.deepLink.rawValue
        case .openUrl: return InboxActionType.openUrl.rawValue
        }
    }

    func testActionTypesMatchCore() {
        for type in [KlaviyoCore.ActionType.openApp, .deepLink, .openUrl] {
            XCTAssertEqual(raw(type), type.rawValue)
        }
        XCTAssertEqual(
            Set(InboxActionType.allCases.map(\.rawValue)),
            ["open_app", "deep_link", "open_url"]
        )
    }

    func testAllowedSchemesMatchCore() {
        XCTAssertEqual(InboxURLSchemeAllowlist.allowedSchemes, KlaviyoCore.openUrlAllowedSchemes)
    }

    func testAllowlistIsCaseInsensitiveAndRejectsUnlistedSchemes() throws {
        XCTAssertTrue(try InboxURLSchemeAllowlist.isAllowed(XCTUnwrap(URL(string: "HTTPS://example.com"))))
        XCTAssertTrue(try InboxURLSchemeAllowlist.isAllowed(XCTUnwrap(URL(string: "mailto:a@b.com"))))
        for url in ["javascript:alert(1)", "file:///etc/passwd", "smsto:123", "myapp://x", "/relative"] {
            XCTAssertFalse(try InboxURLSchemeAllowlist.isAllowed(XCTUnwrap(URL(string: url))), url)
        }
    }
}
