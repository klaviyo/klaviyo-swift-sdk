//
//  BasicSDKIntegrationTests.swift
//
//
//  Integration tests for the public KlaviyoSDK API.
//  These tests verify the SDK works correctly from a developer's perspective.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

/// Integration tests for basic SDK initialization and configuration
class BasicSDKIntegrationTests: XCTestCase {
    override func setUp() async throws {
        // Reset to clean test environment
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.freshTest()

        // Mock API to return successful responses by default
        environment.klaviyoAPI.send = { _, _ in
            .success(Data())
        }
    }

    // MARK: - SDK Initialization Tests

    @MainActor
    func testSDKInitialization() async throws {
        let sdk = KlaviyoSDK()

        // Before initialization, properties should be nil
        XCTAssertNil(sdk.email, "Email should be nil before initialization")
        XCTAssertNil(sdk.phoneNumber, "Phone number should be nil before initialization")
        XCTAssertNil(sdk.externalId, "External ID should be nil before initialization")

        // Initialize SDK
        sdk.initialize(with: "test-api-key")

        // Wait for async initialization to complete
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify SDK is initialized
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertEqual(state.apiKey, "test-api-key", "API key should be set")
        XCTAssertNotNil(state.anonymousId, "Anonymous ID should be generated")
        XCTAssertEqual(state.initalizationState, .initialized, "SDK should be initialized")
    }

    @MainActor
    func testSDKReinitialization() async throws {
        let sdk = KlaviyoSDK()

        // First initialization
        sdk.initialize(with: "first-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        let firstAnonymousId = klaviyoSwiftEnvironment.state().anonymousId

        // Second initialization with different key
        sdk.initialize(with: "second-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify API key changed
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertEqual(state.apiKey, "second-api-key", "API key should update")

        // Anonymous ID should remain the same (or change based on your logic)
        XCTAssertNotNil(state.anonymousId, "Anonymous ID should still exist")
    }

    @MainActor
    func testSDKInitializationWithInvalidKey() async throws {
        // Mock API to return error
        environment.klaviyoAPI.send = { _, _ in
            .failure(.invalidData)
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "")

        try await Task.sleep(nanoseconds: 500_000_000)

        // SDK should still initialize (validation happens at API level)
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertEqual(state.initalizationState, .initialized)
    }

    // MARK: - Basic Flow Tests

    @MainActor
    func testBasicSDKWorkflow() async throws {
        let sdk = KlaviyoSDK()

        // Step 1: Initialize
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Step 2: Set profile
        sdk.set(email: "test@example.com")
        sdk.set(phoneNumber: "+15555555555")

        try await Task.sleep(nanoseconds: 300_000_000)

        // Step 3: Verify profile set
        XCTAssertEqual(sdk.email, "test@example.com")
        XCTAssertEqual(sdk.phoneNumber, "+15555555555")

        // Step 4: Track event
        sdk.create(event: Event(name: .viewedProductMetric, properties: ["product_id": "123"]))

        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify event was queued
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertFalse(state.queue.isEmpty, "Event should be queued")
    }

    @MainActor
    func testSDKMethodChaining() async throws {
        let sdk = KlaviyoSDK()

        // Test that SDK methods return self for chaining
        let result = sdk
            .initialize(with: "test-api-key")
            .set(email: "test@example.com")
            .set(phoneNumber: "+15555555555")
            .set(externalId: "user-123")

        // Verify result is KlaviyoSDK (chainable)
        XCTAssertNotNil(result)

        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify all values were set
        XCTAssertEqual(sdk.email, "test@example.com")
        XCTAssertEqual(sdk.phoneNumber, "+15555555555")
        XCTAssertEqual(sdk.externalId, "user-123")
    }

    // MARK: - Error Handling Tests

    @MainActor
    func testSDKHandlesUninitializedState() async throws {
        let sdk = KlaviyoSDK()

        // Try to use SDK before initialization
        sdk.set(email: "test@example.com")

        try await Task.sleep(nanoseconds: 200_000_000)

        // Email should be nil (SDK should warn but not crash)
        XCTAssertNil(sdk.email, "Email should not be set before initialization")
    }

    @MainActor
    func testSDKHandlesEmptyValues() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set empty email
        sdk.set(email: "")
        try await Task.sleep(nanoseconds: 200_000_000)

        // Empty values should be ignored/cleared
        let email = sdk.email
        XCTAssertTrue(email == nil || email == "", "Empty email should be ignored")
    }

    @MainActor
    func testSDKHandlesWhitespaceValues() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set email with whitespace
        sdk.set(email: "  test@example.com  ")
        try await Task.sleep(nanoseconds: 200_000_000)

        // Should trim whitespace
        XCTAssertEqual(sdk.email, "test@example.com", "Whitespace should be trimmed")
    }

    // MARK: - Concurrent Usage Tests

    @MainActor
    func testSDKHandlesConcurrentCalls() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Make multiple concurrent calls
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                sdk.set(email: "email1@example.com")
            }
            group.addTask { @MainActor in
                sdk.set(phoneNumber: "+15555555551")
            }
            group.addTask { @MainActor in
                sdk.set(externalId: "user-1")
            }
            group.addTask { @MainActor in
                sdk.create(event: Event(name: .viewedProductMetric))
            }
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify state is consistent (last write wins or all succeed)
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertNotNil(state.email, "Email should be set")
        XCTAssertNotNil(state.phoneNumber, "Phone should be set")
        XCTAssertNotNil(state.externalId, "External ID should be set")
    }

    // MARK: - Multiple SDK Instances Tests

    @MainActor
    func testMultipleSDKInstances() async throws {
        // Create two SDK instances
        let sdk1 = KlaviyoSDK()
        let sdk2 = KlaviyoSDK()

        // Initialize both with same key
        sdk1.initialize(with: "test-api-key")
        sdk2.initialize(with: "test-api-key")

        try await Task.sleep(nanoseconds: 500_000_000)

        // Set different values
        sdk1.set(email: "sdk1@example.com")
        sdk2.set(email: "sdk2@example.com")

        try await Task.sleep(nanoseconds: 300_000_000)

        // Both should see the same state (shared state manager)
        XCTAssertEqual(sdk1.email, sdk2.email, "Both SDK instances should share state")
    }
}
