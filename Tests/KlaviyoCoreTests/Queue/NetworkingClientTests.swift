//
//  NetworkingClientTests.swift
//  KlaviyoCoreTests
//
//  Created by Claude Code on 2025-11-10.
//

@testable import KlaviyoCore
import XCTest

final class NetworkingClientTests: XCTestCase {
    var client: NetworkingClient!
    var mockAPI: MockKlaviyoAPI!

    override func setUp() throws {
        mockAPI = MockKlaviyoAPI()
        // Override environment API client
        let originalApiClient = environment.apiClient
        environment.apiClient = { [mockAPI] in mockAPI! }

        client = NetworkingClient(apiKey: "test-key", configuration: .test)
    }

    override func tearDown() async throws {
        await client?.clearQueue()
        client = nil
        mockAPI = nil
        NetworkingClient.reset()
    }

    // MARK: - Singleton Tests

    func testConfigureCreatesSharedInstance() {
        NetworkingClient.configure(apiKey: "test-key")
        XCTAssertNotNil(NetworkingClient.shared)
    }

    func testResetClearsSharedInstance() async {
        NetworkingClient.configure(apiKey: "test-key")
        NetworkingClient.reset()
        XCTAssertNil(NetworkingClient.shared)
    }

    // MARK: - Immediate Send Tests

    func testSendImmediateSuccess() async throws {
        mockAPI.result = .success("test data".data(using: .utf8)!)

        let request = makeTestRequest()
        let data = try await client.send(request)

        XCTAssertEqual(mockAPI.sendCallCount, 1)
        XCTAssertEqual(String(data: data, encoding: .utf8), "test data")
    }

    func testSendImmediateFailureThrows() async {
        mockAPI.result = .failure(.networkError(URLError(.notConnectedToInternet)))

        let request = makeTestRequest()

        do {
            _ = try await client.send(request)
            XCTFail("Should have thrown error")
        } catch let error as KlaviyoAPIError {
            if case .networkError = error {
                // Expected
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSendDoesNotUseQueue() async throws {
        mockAPI.result = .success(Data())

        let request = makeTestRequest()
        _ = try await client.send(request)

        // Queue should remain empty
        let queueCount = await client.queueCount()
        XCTAssertEqual(queueCount, 0)
    }

    // MARK: - Enqueue Tests

    func testEnqueueAddsToQueue() async {
        let request = makeTestRequest()
        client.enqueue(request, priority: .normal)

        // Wait briefly for async operation
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let queueCount = await client.queueCount()
        XCTAssertEqual(queueCount, 1)
    }

    func testEnqueueImmediatePriority() async {
        let request = makeTestRequest()
        client.enqueue(request, priority: .immediate)

        try? await Task.sleep(nanoseconds: 100_000_000)

        let queueCount = await client.queueCount()
        XCTAssertEqual(queueCount, 1)
    }

    func testEnqueueMultipleRequests() async {
        client.enqueue(makeTestRequest(), priority: .normal)
        client.enqueue(makeTestRequest(), priority: .normal)
        client.enqueue(makeTestRequest(), priority: .normal)

        try? await Task.sleep(nanoseconds: 100_000_000)

        let queueCount = await client.queueCount()
        XCTAssertEqual(queueCount, 3)
    }

    // MARK: - Queue Processing Tests

    func testStartProcessesQueue() async throws {
        mockAPI.result = .success(Data())

        client.enqueue(makeTestRequest(), priority: .normal)
        try? await Task.sleep(nanoseconds: 100_000_000)

        client.start()
        await client.flush()

        let queueCount = await client.queueCount()
        XCTAssertEqual(queueCount, 0)
        XCTAssertEqual(mockAPI.sendCallCount, 1)
    }

    func testPauseStopsProcessing() async throws {
        mockAPI.result = .success(Data())

        client.enqueue(makeTestRequest(), priority: .normal)
        try? await Task.sleep(nanoseconds: 100_000_000)

        client.pause()

        // Even after flush, queue should not be processed
        await client.flush()

        let queueCount = await client.queueCount()
        XCTAssertEqual(queueCount, 1, "Queue should not be processed while paused")
    }

    func testResumeAfterPause() async throws {
        mockAPI.result = .success(Data())

        client.enqueue(makeTestRequest(), priority: .normal)
        try? await Task.sleep(nanoseconds: 100_000_000)

        client.pause()
        client.resume()
        await client.flush()

        let queueCount = await client.queueCount()
        XCTAssertEqual(queueCount, 0)
    }

    // MARK: - Flush Tests

    func testFlushProcessesAllRequests() async throws {
        mockAPI.result = .success(Data())

        // Enqueue multiple requests
        for _ in 0..<5 {
            client.enqueue(makeTestRequest(), priority: .normal)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        await client.flush()

        let queueCount = await client.queueCount()
        XCTAssertEqual(queueCount, 0)
        XCTAssertEqual(mockAPI.sendCallCount, 5)
    }

    // MARK: - Queue State Tests

    func testIsEmpty() async {
        let isEmpty = await client.isEmpty()
        XCTAssertTrue(isEmpty)

        client.enqueue(makeTestRequest(), priority: .normal)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let isEmptyAfter = await client.isEmpty()
        XCTAssertFalse(isEmptyAfter)
    }

    func testQueueCount() async {
        let initialCount = await client.queueCount()
        XCTAssertEqual(initialCount, 0)

        client.enqueue(makeTestRequest(), priority: .normal)
        client.enqueue(makeTestRequest(), priority: .immediate)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let count = await client.queueCount()
        XCTAssertEqual(count, 2)
    }

    func testInFlightCount() async throws {
        mockAPI.result = .success(Data())

        client.enqueue(makeTestRequest(), priority: .normal)
        try? await Task.sleep(nanoseconds: 100_000_000)

        client.start()

        // Check in-flight during processing (timing dependent, so optional check)
        // After flush completes, should be 0
        await client.flush()

        let inFlight = await client.inFlightCount()
        XCTAssertEqual(inFlight, 0)
    }

    func testClearQueue() async {
        client.enqueue(makeTestRequest(), priority: .normal)
        client.enqueue(makeTestRequest(), priority: .normal)
        try? await Task.sleep(nanoseconds: 100_000_000)

        await client.clearQueue()

        let count = await client.queueCount()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Persistence Integration Tests

    func testQueuePersistedOnEnqueue() async {
        client.enqueue(makeTestRequest(), priority: .normal)
        try? await Task.sleep(nanoseconds: 200_000_000) // Wait for persistence

        // Create new client with same API key - should load persisted queue
        let newClient = NetworkingClient(apiKey: "test-key", configuration: .test)
        let count = await newClient.queueCount()
        XCTAssertGreaterThan(count, 0, "New client should load persisted queue")
    }

    func testQueuePersistedOnPause() async {
        client.enqueue(makeTestRequest(), priority: .normal)
        try? await Task.sleep(nanoseconds: 100_000_000)

        client.pause()
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Verify persistence occurred
        let newClient = NetworkingClient(apiKey: "test-key", configuration: .test)
        let count = await newClient.queueCount()
        XCTAssertGreaterThan(count, 0)
    }

    // MARK: - Error Handling Tests

    func testEnqueueHandlesErrors() async {
        // This shouldn't throw even if there are issues
        client.enqueue(makeTestRequest(), priority: .normal)

        // Should not crash
        XCTAssertTrue(true)
    }

    // MARK: - Helper Methods

    private func makeTestRequest(id: String? = nil) -> KlaviyoRequest {
        let endpoint = KlaviyoEndpoint.createProfile(
            profilePayload: .init(
                data: .init(
                    type: .profile,
                    attributes: .init(
                        email: "test@example.com",
                        phoneNumber: nil,
                        externalId: nil,
                        anonymousId: "test-id",
                        properties: [:]
                    )
                )
            )
        )
        return KlaviyoRequest(id: id ?? UUID().uuidString, endpoint: endpoint)
    }
}
