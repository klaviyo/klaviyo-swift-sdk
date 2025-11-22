//
//  PushActionButtonTests.swift
//
//
//  Created by Ajay Subramanya on 11/21/24.
//

@testable import KlaviyoSwift
import UserNotifications
import XCTest

@available(iOS 10.0, *)
final class PushActionButtonTests: XCTestCase {
    // MARK: - Category Tests

    func testCategoryIdentifiers() {
        XCTAssertEqual(KlaviyoPushCategory.acceptDecline.identifier, "com.klaviyo.category.acceptDecline")
        XCTAssertEqual(KlaviyoPushCategory.yesNo.identifier, "com.klaviyo.category.yesNo")
        XCTAssertEqual(KlaviyoPushCategory.confirmCancel.identifier, "com.klaviyo.category.confirmCancel")
        XCTAssertEqual(KlaviyoPushCategory.viewDismiss.identifier, "com.klaviyo.category.viewDismiss")
    }

    func testCategoryCreation() {
        let category = KlaviyoPushCategory.acceptDecline.createNotificationCategory()

        XCTAssertEqual(category.identifier, "com.klaviyo.category.acceptDecline")
        XCTAssertEqual(category.actions.count, 2)

        let actionIdentifiers = Set(category.actions.map(\.identifier))
        XCTAssertTrue(actionIdentifiers.contains("com.klaviyo.action.accept"))
        XCTAssertTrue(actionIdentifiers.contains("com.klaviyo.action.decline"))
    }

    func testActionForegroundBehavior() {
        XCTAssertTrue(KlaviyoPushAction.accept.opensForeground)
        XCTAssertTrue(KlaviyoPushAction.yes.opensForeground)
        XCTAssertTrue(KlaviyoPushAction.confirm.opensForeground)
        XCTAssertTrue(KlaviyoPushAction.view.opensForeground)

        XCTAssertFalse(KlaviyoPushAction.decline.opensForeground)
        XCTAssertFalse(KlaviyoPushAction.no.opensForeground)
        XCTAssertFalse(KlaviyoPushAction.cancel.opensForeground)
        XCTAssertFalse(KlaviyoPushAction.dismiss.opensForeground)
    }

    // MARK: - UNNotificationResponse Extension Tests

    func testIsActionButtonTap() throws {
        // Action button tap
        let actionButtonResponse = try UNNotificationResponse.with(
            userInfo: ["body": ["_k": "test"]],
            actionIdentifier: "com.klaviyo.action.view"
        )
        XCTAssertTrue(actionButtonResponse.isActionButtonTap)

        // Default tap (not an action button)
        let defaultResponse = try UNNotificationResponse.with(
            userInfo: ["body": ["_k": "test"]],
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )
        XCTAssertFalse(defaultResponse.isActionButtonTap)

        // Dismiss action (not an action button)
        let dismissResponse = try UNNotificationResponse.with(
            userInfo: ["body": ["_k": "test"]],
            actionIdentifier: UNNotificationDismissActionIdentifier
        )
        XCTAssertFalse(dismissResponse.isActionButtonTap)
    }

    func testKlaviyoActionIdentifier() throws {
        // Klaviyo action
        let klaviyoResponse = try UNNotificationResponse.with(
            userInfo: ["body": ["_k": "test"]],
            actionIdentifier: "com.klaviyo.action.view"
        )
        XCTAssertEqual(klaviyoResponse.klaviyoActionIdentifier, "com.klaviyo.action.view")

        // Non-Klaviyo action
        let customResponse = try UNNotificationResponse.with(
            userInfo: ["body": ["_k": "test"]],
            actionIdentifier: "CUSTOM_ACTION"
        )
        XCTAssertNil(customResponse.klaviyoActionIdentifier)

        // Default tap
        let defaultResponse = try UNNotificationResponse.with(
            userInfo: ["body": ["_k": "test"]],
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )
        XCTAssertNil(defaultResponse.klaviyoActionIdentifier)
    }

    func testActionButtonURL() throws {
        // With action-specific URL
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test",
                "actions": [
                    "com.klaviyo.action.view": [
                        "url": "myapp://orders/12345"
                    ]
                ]
            ]
        ]

        let response = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: "com.klaviyo.action.view"
        )

        XCTAssertEqual(response.actionButtonURL?.absoluteString, "myapp://orders/12345")

        // Without action-specific URL
        let userInfoNoURL: [AnyHashable: Any] = [
            "body": [
                "_k": "test",
                "actions": [
                    "com.klaviyo.action.dismiss": [:]
                ]
            ]
        ]

        let responseNoURL = try UNNotificationResponse.with(
            userInfo: userInfoNoURL,
            actionIdentifier: "com.klaviyo.action.dismiss"
        )

        XCTAssertNil(responseNoURL.actionButtonURL)

        // Default tap (not action button)
        let defaultResponse = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        XCTAssertNil(defaultResponse.actionButtonURL)
    }

    func testActionButtonMetadata() throws {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test",
                "actions": [
                    "com.klaviyo.action.view": [
                        "url": "myapp://orders/12345",
                        "custom_data": "test_value"
                    ]
                ]
            ]
        ]

        let response = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: "com.klaviyo.action.view"
        )

        let metadata = response.actionButtonMetadata
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?["url"] as? String, "myapp://orders/12345")
        XCTAssertEqual(metadata?["custom_data"] as? String, "test_value")
    }

    // MARK: - Event Type Tests

    func testOpenedPushActionEventName() {
        let event = Event(name: ._openedPushAction, properties: ["test": "value"])
        XCTAssertEqual(event.metric.name.value, "$opened_push_action")
    }

    func testRegularOpenedPushEventName() {
        let event = Event(name: ._openedPush, properties: ["test": "value"])
        XCTAssertEqual(event.metric.name.value, "$opened_push")
    }

    // MARK: - Integration Tests

    func testBackwardsCompatibility() throws {
        // Regular push tap should still work as before
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test",
                "url": "myapp://default"
            ]
        ]

        let defaultResponse = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        XCTAssertTrue(defaultResponse.isKlaviyoNotification)
        XCTAssertFalse(defaultResponse.isActionButtonTap)
        XCTAssertEqual(defaultResponse.klaviyoDeepLinkURL?.absoluteString, "myapp://default")
        XCTAssertNil(defaultResponse.actionButtonURL)
    }

    func testActionButtonTakesP

    recedence() throws {
        // When both default URL and action URL exist, action URL should be used for action buttons
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test",
                "url": "myapp://default",
                "actions": [
                    "com.klaviyo.action.view": [
                        "url": "myapp://specific-action"
                    ]
                ]
            ]
        ]

        let actionResponse = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: "com.klaviyo.action.view"
        )

        XCTAssertTrue(actionResponse.isActionButtonTap)
        XCTAssertEqual(actionResponse.actionButtonURL?.absoluteString, "myapp://specific-action")
        XCTAssertEqual(actionResponse.klaviyoDeepLinkURL?.absoluteString, "myapp://default")
    }
}
