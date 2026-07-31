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

    func testParseActionButtons_RendersOpenAppWithStrayURL() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.openapp_with_url",
                        "label": "Open App",
                        "action": "open_app",
                        "url": "myapp://invalid" // openApp ignores the url field
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

        XCTAssertEqual(result?.count, 2, "A stray url on open_app must not delete the button")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.openapp_with_url")
    }

    func testParseActionButtons_RendersDeepLinkWithoutURL() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.deeplink_without_url",
                        "label": "Deep Link",
                        "action": "deep_link"
                        // Missing URL — the tap falls through to opening the app
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid Button",
                        "action": "open_app"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertEqual(result?.count, 2, "A missing deep_link url must not delete the button")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.deeplink_without_url")
        XCTAssertNil(result?.first?.url)
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

    func testParseActionButtons_ParsesValidOpenUrlButton() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.open_url",
                        "label": "Visit Site",
                        "action": "open_url",
                        "url": "https://example.com/sale"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "Should parse valid open_url button")
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.action, .openUrl)
        XCTAssertEqual(result?.first?.url, "https://example.com/sale")
    }

    // MARK: - Render eligibility is independent of URL validity

    /// A URL the SDK cannot open must not delete the button the marketer configured.
    /// `URL(string: "www.cnn.com")` parses but has a nil scheme, so the allowlist check
    /// used to reject it and — when it was the only button — the notification rendered
    /// with no buttons at all.
    func testParseActionButtons_RendersOpenUrlButtonWithSchemelessURL() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.schemeless",
                        "label": "Read More",
                        "action": "open_url",
                        "url": "www.cnn.com"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertEqual(result?.count, 1, "A scheme-less URL must not delete the button")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.schemeless")
        XCTAssertEqual(result?.first?.label, "Read More")
        XCTAssertEqual(result?.first?.url, "www.cnn.com", "The raw URL is preserved, not normalized")
    }

    func testParseActionButtons_RendersOpenUrlWithoutURL() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.openurl_no_url",
                        "label": "Visit Site",
                        "action": "open_url"
                        // Missing URL — the tap falls through to opening the app
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid Button",
                        "action": "open_url",
                        "url": "https://example.com"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertEqual(result?.count, 2, "A missing open_url url must not delete the button")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.openurl_no_url")
    }

    /// A blocked scheme must still render the button — the allowlist is enforced at dispatch
    /// time, so the tap opens the app instead of the URL. See
    /// `KlaviyoSDKTests.testHandleActionButtonTap_OpenUrlButtonWithBlockedSchemeDoesNotDispatch`.
    func testParseActionButtons_RendersOpenUrlWithBlockedScheme() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.openurl_custom_scheme",
                        "label": "Bad",
                        "action": "open_url",
                        "url": "klaviyotest://forms"
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid",
                        "action": "open_url",
                        "url": "https://example.com"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertEqual(result?.count, 2, "A blocked scheme must not delete the button")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.openurl_custom_scheme")
    }

    // MARK: - Allowlisted non-web open_url schemes

    func testParseActionButtons_AcceptsOpenUrlWithMailtoScheme() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.mailto",
                        "label": "Email Us",
                        "action": "open_url",
                        "url": "mailto:support@example.com"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "mailto: should be accepted by open_url")
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.mailto")
        XCTAssertEqual(result?.first?.url, "mailto:support@example.com")
    }

    func testParseActionButtons_AcceptsOpenUrlWithTelScheme() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.tel",
                        "label": "Call Us",
                        "action": "open_url",
                        "url": "tel:+15551234567"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "tel: should be accepted by open_url")
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.tel")
        XCTAssertEqual(result?.first?.url, "tel:+15551234567")
    }

    func testParseActionButtons_AcceptsOpenUrlWithSmsScheme() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.sms",
                        "label": "Text Us",
                        "action": "open_url",
                        "url": "sms:+15551234567"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "sms: should be accepted by open_url")
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.sms")
    }

    func testParseActionButtons_RendersOpenUrlWithIntentScheme() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.intent",
                        "label": "Bad",
                        "action": "open_url",
                        "url": "intent://example"
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid",
                        "action": "open_url",
                        "url": "https://example.com"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertEqual(result?.count, 2, "intent: is blocked at dispatch time, not at render time")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.intent")
    }

    func testParseActionButtons_RendersOpenUrlWithJavascriptScheme() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.js",
                        "label": "Bad",
                        "action": "open_url",
                        "url": "javascript:alert(1)"
                    ],
                    [
                        "id": "com.klaviyo.test.valid",
                        "label": "Valid",
                        "action": "open_url",
                        "url": "https://example.com"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertEqual(result?.count, 2, "javascript: is blocked at dispatch time, not at render time")
        XCTAssertEqual(result?.first?.id, "com.klaviyo.test.js")
    }

    func testParseActionButtons_AllowsDeepLinkWithHttpScheme() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": {},
                "action_buttons": [
                    [
                        "id": "com.klaviyo.test.deeplink_http",
                        "label": "Deep link with http",
                        "action": "deep_link",
                        "url": "https://www.google.com"
                    ]
                ]
            ]
        ]

        let result = KlaviyoActionButtonParser.parseActionButtons(from: userInfo)

        XCTAssertNotNil(result, "Deep link should accept any URL scheme — customer handler decides")
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.action, .deepLink)
    }
}
