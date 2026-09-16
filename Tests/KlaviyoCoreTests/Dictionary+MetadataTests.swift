//
//  Dictionary+MetadataTests.swift
//  klaviyo-swift-sdk
//
//  Created by Ajay Subramanya on 10/10/25.
//

import KlaviyoCore
import XCTest

final class DictionaryMetadataTests: XCTestCase {
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
    }

    override func tearDown() {
        environment = KlaviyoEnvironment.test()
        super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func testAppendMetadataWithEmptyProperties() throws {
        // Given
        let properties: [String: Any] = [:]

        // When
        let enriched = try XCTUnwrap(properties.appendMetadataToProperties(pushToken: nil))

        // Then
        XCTAssertEqual(enriched.count, 12, "Should have 12 metadata fields")
        XCTAssertNotNil(enriched["Device ID"])
        XCTAssertNotNil(enriched["Device Manufacturer"])
        XCTAssertNotNil(enriched["Device Model"])
        XCTAssertNotNil(enriched["OS Name"])
        XCTAssertNotNil(enriched["OS Version"])
        XCTAssertNotNil(enriched["SDK Name"])
        XCTAssertNotNil(enriched["SDK Version"])
        XCTAssertNotNil(enriched["App Name"])
        XCTAssertNotNil(enriched["App ID"])
        XCTAssertNotNil(enriched["App Version"])
        XCTAssertNotNil(enriched["App Build"])
    }

    func testAppendMetadataPreservesOriginalProperties() throws {
        // Given
        let properties: [String: Any] = [
            "custom_prop": "custom_value",
            "event_id": 123,
            "nested": ["key": "value"]
        ]

        // When
        let enriched = try XCTUnwrap(properties.appendMetadataToProperties(pushToken: nil))

        // Then
        XCTAssertEqual(enriched["custom_prop"] as? String, "custom_value")
        XCTAssertEqual(enriched["event_id"] as? Int, 123)
        XCTAssertNotNil(enriched["nested"] as? [String: String])
        XCTAssertEqual(enriched.count, 15, "Should have 3 original + 12 metadata fields")
    }

    func testAppendMetadataWithPushToken() throws {
        // Given
        let properties: [String: Any] = [:]
        let testToken = "test_push_token_12345"

        // When
        let enriched = try XCTUnwrap(properties.appendMetadataToProperties(pushToken: testToken))

        // Then
        XCTAssertEqual(enriched["Push Token"] as? String, testToken)
    }

    func testAppendMetadataWithNilPushToken() throws {
        // Given
        let properties: [String: Any] = [:]

        // When
        let enriched = try XCTUnwrap(properties.appendMetadataToProperties(pushToken: nil))

        // Then
        XCTAssertEqual(enriched["Push Token"] as? String, "")
    }

    func testAppendMetadataOverridesOriginalValues() throws {
        // Given - properties with keys that conflict with metadata
        let properties: [String: Any] = [
            "Device ID": "old_device_id",
            "App Name": "old_app_name",
            "custom_prop": "keep_this"
        ]

        // When
        let enriched = try XCTUnwrap(properties.appendMetadataToProperties(pushToken: nil))

        // Then - metadata values should override original values
        XCTAssertNotEqual(enriched["Device ID"] as? String, "old_device_id")
        XCTAssertNotEqual(enriched["App Name"] as? String, "old_app_name")
        XCTAssertEqual(enriched["custom_prop"] as? String, "keep_this", "Non-conflicting properties should be preserved")
    }

    // MARK: - Metadata Field Tests

    func testAppendMetadataDeviceIDFromEnvironment() {
        // Given
        let properties: [String: Any] = [:]

        // When
        let enriched = properties.appendMetadataToProperties(pushToken: nil)

        // Then
        let deviceID = enriched?["Device ID"] as? String
        XCTAssertNotNil(deviceID)
        XCTAssertFalse(deviceID?.isEmpty ?? true)
    }

    func testAppendMetadataSDKNameIsSwift() {
        // Given
        let properties: [String: Any] = [:]

        // When
        let enriched = properties.appendMetadataToProperties(pushToken: nil)

        // Then
        XCTAssertEqual(enriched?["SDK Name"] as? String, "swift")
    }

    func testAppendMetadataAllFieldsAreStrings() {
        // Given
        let properties: [String: Any] = [:]

        // When
        let enriched = properties.appendMetadataToProperties(pushToken: "token")

        // Then
        let metadataKeys = [
            "Device ID", "Device Manufacturer", "Device Model",
            "OS Name", "OS Version", "SDK Name", "SDK Version",
            "App Name", "App ID", "App Version", "App Build", "Push Token"
        ]

        for key in metadataKeys {
            XCTAssertTrue(enriched?[key] is String, "\(key) should be a String")
        }
    }

    // MARK: - Edge Cases

    func testAppendMetadataWithComplexNestedProperties() throws {
        // Given
        let properties: [String: Any] = [
            "user": [
                "name": "Test User",
                "preferences": [
                    "theme": "dark",
                    "notifications": true
                ]
            ],
            "items": [1, 2, 3],
            "metadata": [
                "version": "1.0"
            ]
        ]

        // When
        let enriched = try XCTUnwrap(properties.appendMetadataToProperties(pushToken: "token123"))

        // Then
        XCTAssertNotNil(enriched["user"])
        XCTAssertNotNil(enriched["items"])
        XCTAssertNotNil(enriched["metadata"])
        XCTAssertNotNil(enriched["Device ID"])
        XCTAssertEqual(enriched["Push Token"] as? String, "token123")
    }

    func testAppendMetadataWithSpecialCharacters() throws {
        // Given
        let properties: [String: Any] = [
            "emoji": "🎉",
            "unicode": "你好",
            "special": "hello@world.com"
        ]

        // When
        let enriched = try XCTUnwrap(properties.appendMetadataToProperties(pushToken: "token🔑"))

        // Then
        XCTAssertEqual(enriched["emoji"] as? String, "🎉")
        XCTAssertEqual(enriched["unicode"] as? String, "你好")
        XCTAssertEqual(enriched["special"] as? String, "hello@world.com")
        XCTAssertEqual(enriched["Push Token"] as? String, "token🔑")
    }
}
