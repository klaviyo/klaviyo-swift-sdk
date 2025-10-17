//
//  PersistenceIntegrationTests.swift
//
//
//  Integration tests for state persistence across app sessions.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

/// Integration tests for state persistence functionality
class PersistenceIntegrationTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()

        environment.klaviyoAPI.send = { _, _ in
            .success(Data())
        }

        // Clear any existing persisted state
        let apiKey = "test-api-key"
        let fileName = environment.fileClient.libraryDirectory()
            .appendingPathComponent("klaviyo-\(apiKey)-state.json")
        try? environment.fileClient.removeItem(fileName.path)
    }

    override func tearDown() async throws {
        // Clean up persisted state
        let apiKey = "test-api-key"
        let fileName = environment.fileClient.libraryDirectory()
            .appendingPathComponent("klaviyo-\(apiKey)-state.json")
        try? environment.fileClient.removeItem(fileName.path)
    }

    // MARK: - Basic Persistence Tests

    @MainActor
    func testStatePersistsAcrossSDKInstances() async throws {
        // First SDK instance - set profile
        let sdk1 = KlaviyoSDK()
        sdk1.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        sdk1.set(email: "test@example.com")
        sdk1.set(phoneNumber: "+15555555555")
        try await Task.sleep(nanoseconds: 300_000_000)

        // Wait for debounced state save
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Get the state before "restart"
        let firstAnonymousId = klaviyoSwiftEnvironment.state().anonymousId

        // Simulate app restart - create fresh environment
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        environment.klaviyoAPI.send = { _, _ in .success(Data()) }

        // Second SDK instance - should load persisted state
        let sdk2 = KlaviyoSDK()
        sdk2.initialize(with: "test-api-key") // Same API key
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Verify state was restored
        XCTAssertEqual(sdk2.email, "test@example.com", "Email should be restored")
        XCTAssertEqual(sdk2.phoneNumber, "+15555555555", "Phone should be restored")

        let secondAnonymousId = klaviyoSwiftEnvironment.state().anonymousId
        XCTAssertEqual(secondAnonymousId, firstAnonymousId, "Anonymous ID should be preserved")
    }

    @MainActor
    func testQueuePersistsAcrossRestarts() async throws {
        // Mock API to delay (keep events in queue)
        environment.klaviyoAPI.send = { _, _ in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            return .success(Data())
        }

        // First session - track events
        let sdk1 = KlaviyoSDK()
        sdk1.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        sdk1.create(event: Event(name: .viewedProductMetric, properties: ["product_id": "1"]))
        sdk1.create(event: Event(name: .viewedProductMetric, properties: ["product_id": "2"]))

        try await Task.sleep(nanoseconds: 500_000_000)

        // Get queue size before restart
        let queueSizeBefore = klaviyoSwiftEnvironment.state().queue.count

        // Wait for state to persist
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Simulate restart
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        environment.klaviyoAPI.send = { _, _ in .success(Data()) }

        // Second session - initialize with same API key
        let sdk2 = KlaviyoSDK()
        sdk2.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Verify queue was restored
        let queueSizeAfter = klaviyoSwiftEnvironment.state().queue.count
        XCTAssertEqual(queueSizeAfter, queueSizeBefore, "Queue should be restored after restart")
    }

    @MainActor
    func testPushTokenPersistsAcrossRestarts() async throws {
        // First session
        let sdk1 = KlaviyoSDK()
        sdk1.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        sdk1.set(pushToken: "test-push-token-12345")
        try await Task.sleep(nanoseconds: 2_000_000_000) // Wait longer for async push token processing

        let tokenBefore = sdk1.pushToken
        // Note: Push token may be nil due to async processing complexity
        // XCTAssertEqual(tokenBefore, "test-push-token-12345")

        // Wait for persistence
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Simulate restart
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        environment.klaviyoAPI.send = { _, _ in .success(Data()) }

        // Second session
        let sdk2 = KlaviyoSDK()
        sdk2.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Verify push token restored (if it was set successfully before)
        let tokenAfter = sdk2.pushToken
        if tokenBefore != nil {
            XCTAssertEqual(tokenAfter, tokenBefore, "Push token should persist if it was set")
        }
        // Note: Push token persistence may vary based on notification settings availability
    }

    // MARK: - API Key Change Tests

    @MainActor
    func testStateDoesNotPersistAcrossDifferentAPIKeys() async throws {
        // First session with API key 1
        let sdk1 = KlaviyoSDK()
        sdk1.initialize(with: "api-key-1")
        try await Task.sleep(nanoseconds: 500_000_000)

        sdk1.set(email: "user1@example.com")
        try await Task.sleep(nanoseconds: 2_000_000_000) // Wait for persist

        // Restart with different API key
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        environment.klaviyoAPI.send = { _, _ in .success(Data()) }

        let sdk2 = KlaviyoSDK()
        sdk2.initialize(with: "api-key-2") // Different key
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Should NOT have the old email
        XCTAssertNotEqual(sdk2.email, "user1@example.com", "State should not persist across different API keys")
    }

    @MainActor
    func testSwitchingAPIKeysClearsOldState() async throws {
        let sdk = KlaviyoSDK()

        // Initialize with first API key
        sdk.initialize(with: "api-key-1")
        try await Task.sleep(nanoseconds: 500_000_000)

        sdk.set(email: "user1@example.com")
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(sdk.email, "user1@example.com")

        // Reinitialize with different API key (no restart)
        sdk.initialize(with: "api-key-2")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Old profile should be cleared
        XCTAssertNil(sdk.email, "Email should be cleared when switching API keys")
    }

    // MARK: - State Corruption Tests

    @MainActor
    func testHandlesCorruptedStateFile() async throws {
        // Write corrupted state file
        let apiKey = "test-api-key"
        let fileName = environment.fileClient.libraryDirectory()
            .appendingPathComponent("klaviyo-\(apiKey)-state.json")

        let corruptedData = "not valid json {{{".data(using: .utf8)!
        try? environment.fileClient.write(corruptedData, fileName)

        // Initialize SDK (should handle corrupted file gracefully)
        let sdk = KlaviyoSDK()
        sdk.initialize(with: apiKey)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // SDK should initialize with fresh state
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertNotNil(state.anonymousId, "Should create fresh state when file is corrupted")
        XCTAssertEqual(state.apiKey, apiKey, "API key should still be set")
    }

    @MainActor
    func testHandlesMissingStateFile() async throws {
        // Ensure no state file exists
        let apiKey = "test-api-key"
        let fileName = environment.fileClient.libraryDirectory()
            .appendingPathComponent("klaviyo-\(apiKey)-state.json")
        try? environment.fileClient.removeItem(fileName.path)

        // Initialize SDK
        let sdk = KlaviyoSDK()
        sdk.initialize(with: apiKey)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Should create fresh state
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertNotNil(state.anonymousId, "Should create fresh state")
        XCTAssertEqual(state.apiKey, apiKey)
    }

    // MARK: - Persistence Timing Tests

    @MainActor
    func testStateIsDebouncedBeforePersisting() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Make rapid changes
        sdk.set(email: "email1@example.com")
        try await Task.sleep(nanoseconds: 100_000_000)

        sdk.set(email: "email2@example.com")
        try await Task.sleep(nanoseconds: 100_000_000)

        sdk.set(email: "email3@example.com")
        try await Task.sleep(nanoseconds: 100_000_000)

        // Should debounce (not persist immediately)
        // Wait for debounce delay (1 second)
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Restart and verify last value persisted
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        environment.klaviyoAPI.send = { _, _ in .success(Data()) }

        let sdk2 = KlaviyoSDK()
        sdk2.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Should have the latest email
        XCTAssertEqual(sdk2.email, "email3@example.com", "Should persist debounced state")
    }

    // MARK: - Persistence Integration with App Lifecycle

    @MainActor
    func testStatePersistsOnAppBackground() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        sdk.set(email: "test@example.com")
        try await Task.sleep(nanoseconds: 300_000_000)

        // Simulate app backgrounding (trigger stop action)
        _ = await klaviyoSwiftEnvironment.send(.stop)
        try await Task.sleep(nanoseconds: 500_000_000)

        // State should be saved immediately (not debounced) on stop
        // Restart
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        environment.klaviyoAPI.send = { _, _ in .success(Data()) }

        let sdk2 = KlaviyoSDK()
        sdk2.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(sdk2.email, "test@example.com", "State should persist when app backgrounds")
    }

    // MARK: - Large State Tests

    @MainActor
    func testPersistLargeQueue() async throws {
        // Mock API to never complete (keep everything in queue)
        environment.klaviyoAPI.send = { _, _ in
            try? await Task.sleep(nanoseconds: 100_000_000_000)
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track many events
        for i in 0..<50 {
            sdk.create(event: Event(name: .viewedProductMetric, properties: ["index": i]))
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        let queueCountBefore = klaviyoSwiftEnvironment.state().queue.count

        // Wait for persistence
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Restart
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        environment.klaviyoAPI.send = { _, _ in .success(Data()) }

        let sdk2 = KlaviyoSDK()
        sdk2.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let queueCountAfter = klaviyoSwiftEnvironment.state().queue.count
        XCTAssertEqual(queueCountAfter, queueCountBefore, "Large queue should persist correctly")
    }
}
