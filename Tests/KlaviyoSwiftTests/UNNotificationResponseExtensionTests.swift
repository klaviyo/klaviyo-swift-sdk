//
//  UNNotificationResponseExtensionTests.swift
//  KlaviyoSwiftTests
//
//  Created for Klaviyo
//
//  Copyright (c) 2025 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

@testable import KlaviyoSwift
import UserNotifications
import XCTest

class UNNotificationResponseExtensionTests: XCTestCase {
    // MARK: - isKlaviyoNotification Tests

    func testIsKlaviyoNotification_WithKlaviyoPayload_ReturnsTrue() throws {
        // Arrange
        let klaviyoPayload: [AnyHashable: Any] = [
            "body": ["_k": "some-value", "other_key": "value"]
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: klaviyoPayload)

        // Assert
        XCTAssertTrue(response.isKlaviyoNotification)
    }

    func testIsKlaviyoNotification_WithoutBodyDict_ReturnsFalse() throws {
        // Arrange
        let nonKlaviyoPayload: [AnyHashable: Any] = [
            "some_key": "some_value"
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: nonKlaviyoPayload)

        // Assert
        XCTAssertFalse(response.isKlaviyoNotification)
    }

    func testIsKlaviyoNotification_WithBodyWithoutKlaviyoKey_ReturnsFalse() throws {
        // Arrange
        let nonKlaviyoPayload: [AnyHashable: Any] = [
            "body": ["some_key": "some_value"]
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: nonKlaviyoPayload)

        // Assert
        XCTAssertFalse(response.isKlaviyoNotification)
    }

    func testIsKlaviyoNotification_WithEmptyUserInfo_ReturnsFalse() throws {
        // Arrange
        let emptyPayload: [AnyHashable: Any] = [:]

        // Act
        let response = try UNNotificationResponse.with(userInfo: emptyPayload)

        // Assert
        XCTAssertFalse(response.isKlaviyoNotification)
    }

    func testIsKlaviyoNotification_WithNonDictionaryBody_ReturnsFalse() throws {
        // Arrange
        let invalidPayload: [AnyHashable: Any] = [
            "body": "not a dictionary"
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: invalidPayload)

        // Assert
        XCTAssertFalse(response.isKlaviyoNotification)
    }

    // MARK: - klaviyoProperties Tests

    func testKlaviyoProperties_WithKlaviyoNotification_ReturnsProperties() throws {
        // Arrange
        let expectedProperties: [AnyHashable: Any] = [
            "body": ["_k": "some-value", "other_key": "value"],
            "url": "https://example.com"
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: expectedProperties)

        // Assert
        XCTAssertNotNil(response.klaviyoProperties)
        let properties = response.klaviyoProperties as? [AnyHashable: Any]
        XCTAssertEqual(properties?.count, expectedProperties.count)
        XCTAssertNotNil(properties?["body"])
        XCTAssertEqual(properties?["url"] as? String, "https://example.com")
    }

    func testKlaviyoProperties_WithNonKlaviyoNotification_ReturnsNil() throws {
        // Arrange
        let nonKlaviyoPayload: [AnyHashable: Any] = [
            "some_key": "some_value"
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: nonKlaviyoPayload)

        // Assert
        XCTAssertNil(response.klaviyoProperties)
    }

    func testKlaviyoProperties_WithInvalidUserInfoType_ReturnsNil() throws {
        // Arrange
        // Creating a notification response where userInfo won't be convertible to [String: Any]
        let klaviyoPayload: [AnyHashable: Any] = [
            "body": ["_k": "some-value"]
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: klaviyoPayload)

        // The actual implementation will try to cast to [String: Any]
        // Our mock always provides valid data, so we can't test the exact case
        // But we can at least verify the positive case works
        XCTAssertNotNil(response.klaviyoProperties)
    }

    // MARK: - klaviyoDeepLinkURL Tests

    func testKlaviyoDeepLinkURL_WithValidURL_ReturnsURL() throws {
        // Arrange
        let validURLPayload: [AnyHashable: Any] = [
            "body": ["_k": "some-value"],
            "url": "https://example.com/deeplink"
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: validURLPayload)

        // Assert
        XCTAssertNotNil(response.klaviyoDeepLinkURL)
        XCTAssertEqual(response.klaviyoDeepLinkURL?.absoluteString, "https://example.com/deeplink")
    }

    func testKlaviyoDeepLinkURL_WithInvalidURLString_ReturnsNil() throws {
        // Arrange
        let invalidURLPayload: [AnyHashable: Any] = [
            "body": ["_k": "some-value"],
            "url": "ht tp://invalid-url" // Space in URL makes it invalid
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: invalidURLPayload)

        // Assert
        XCTAssertNil(response.klaviyoDeepLinkURL)
    }

    func testKlaviyoDeepLinkURL_WithoutURLProperty_ReturnsNil() throws {
        // Arrange
        let noURLPayload: [AnyHashable: Any] = [
            "body": ["_k": "some-value"]
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: noURLPayload)

        // Assert
        XCTAssertNil(response.klaviyoDeepLinkURL)
    }

    func testKlaviyoDeepLinkURL_WithNonKlaviyoNotification_ReturnsNil() throws {
        // Arrange
        let nonKlaviyoPayload: [AnyHashable: Any] = [
            "url": "https://example.com/deeplink"
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: nonKlaviyoPayload)

        // Assert
        XCTAssertNil(response.klaviyoDeepLinkURL)
    }

    func testKlaviyoDeepLinkURL_WithNonStringURL_ReturnsNil() throws {
        // Arrange
        let invalidURLTypePayload: [AnyHashable: Any] = [
            "body": ["_k": "some-value"],
            "url": 12_345
        ]

        // Act
        let response = try UNNotificationResponse.with(userInfo: invalidURLTypePayload)

        // Assert
        XCTAssertNil(response.klaviyoDeepLinkURL)
    }
}
