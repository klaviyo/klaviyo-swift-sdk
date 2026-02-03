//
//  KlaviyoActionButtonParserTests.swift
//
//
//  Created by Belle Lim on 1/20/26.
//

@testable import KlaviyoSwiftExtension
import Foundation
import XCTest

class KlaviyoActionButtonParserTests: XCTestCase {
    // MARK: - Missing Required Fields Tests

    func testParseActionButtons_SkipsButtonWithMissingId() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        // Missing "id"
                        "label": "Shop Now",
                        "action": "deep_link",
                        "url": "myapp://sale"
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid Button",
                        "action": "deep_link",
                        "url": "myapp://valid"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "Should return valid buttons when some are invalid")
        XCTAssertEqual(result?.count, 1, "Should skip button with missing id")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.valid", "Should return only valid button")
    }

    func testParseActionButtons_SkipsButtonWithMissingLabel() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.missing_label",
                        // Missing "label"
                        "action": "deep_link",
                        "url": "myapp://sale"
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid Button",
                        "action": "deep_link",
                        "url": "myapp://valid"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "Should return valid buttons when some are invalid")
        XCTAssertEqual(result?.count, 1, "Should skip button with missing label")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.valid", "Should return only valid button")
    }

    func testParseActionButtons_SkipsButtonWithMissingAction() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.missing_action",
                        "label": "Shop Now",
                        // Missing "action"
                        "url": "myapp://sale"
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid Button",
                        "action": "deep_link",
                        "url": "myapp://valid"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "Should return valid buttons when some are invalid")
        XCTAssertEqual(result?.count, 1, "Should skip button with missing action")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.valid", "Should return only valid button")
    }

    func testParseActionButtons_SkipsButtonWithInvalidAction() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.invalid_action",
                        "label": "Shop Now",
                        "action": "invalid_action_type", // Invalid action
                        "url": "myapp://sale"
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid Button",
                        "action": "deep_link",
                        "url": "myapp://valid"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "Should return valid buttons when some are invalid")
        XCTAssertEqual(result?.count, 1, "Should skip button with invalid action")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.valid", "Should return only valid button")
    }

    func testParseActionButtons_SkipsMultipleInvalidButtons() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        // Missing id
                        "label": "First Invalid",
                        "action": "deep_link"
                    ],
                    [
                        "id": "com.klaviyo.test.missing_label",
                        // Missing label
                        "action": "deep_link"
                    ],
                    [
                        "id": "com.klaviyo.test.missing_action",
                        "label": "Third Invalid"
                        // Missing action
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid Button",
                        "action": "deep_link",
                        "url": "myapp://valid"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "Should return valid buttons when some are invalid")
        XCTAssertEqual(result?.count, 1, "Should skip all invalid buttons")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.valid", "Should return only valid button")
    }

    func testParseActionButtons_ReturnsNilWhenAllButtonsInvalid() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        // Missing id
                        "label": "Invalid Button",
                        "action": "deep_link"
                    ],
                    [
                        "id": "com.klaviyo.test.missing_label"
                        // Missing label and action
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNil(result, "Should return nil when all buttons are invalid")
    }

    func testParseActionButtons_SkipsOpenAppWithURL() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.openapp_with_url",
                        "label": "Open App",
                        "action": "open_app",
                        "url": "myapp://invalid" // openApp should not have URL
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid Button",
                        "action": "deep_link",
                        "url": "myapp://valid"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "Should return valid buttons")
        XCTAssertEqual(result?.count, 1, "Should skip openApp button with URL")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.valid", "Should return only valid button")
    }

    func testParseActionButtons_SkipsDeepLinkWithoutURL() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.deeplink_without_url",
                        "label": "Deep Link",
                        "action": "deep_link"
                        // Missing URL - deepLink should have URL
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid Button",
                        "action": "open_app"
                        // No URL for openApp is valid
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "Should return valid buttons")
        XCTAssertEqual(result?.count, 1, "Should skip deepLink button without URL")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.valid", "Should return only valid button")
    }

    // MARK: - Valid Button Tests

    func testParseActionButtons_ParsesValidButtons() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.button1",
                        "label": "Button One",
                        "action": "deep_link",
                        "url": "myapp://one"
                    ],
                    [
                        "id": "com.klaviyo.test.button2",
                        "label": "Button Two",
                        "action": "open_app"
                        // No URL for openApp is valid
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "Should parse valid buttons")
        XCTAssertEqual(result?.count, 2, "Should return both valid buttons")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.button1", "First button should have correct id")
        XCTAssertEqual(result?.first?.label, "Button One", "First button should have correct label")
        XCTAssertEqual(result?.first?.action, .deepLink, "First button should have correct action")
        XCTAssertEqual(result?.first?.url, "myapp://one", "First button should have correct URL")

        XCTAssertEqual(result?.last?.id, "com.klaviyo.test.button2", "Second button should have correct id")
        XCTAssertEqual(result?.last?.label, "Button Two", "Second button should have correct label")
        XCTAssertEqual(result?.last?.action, .openApp, "Second button should have correct action")
        XCTAssertNil(result?.last?.url, "Second button (openApp) should not have URL")
    }
}
