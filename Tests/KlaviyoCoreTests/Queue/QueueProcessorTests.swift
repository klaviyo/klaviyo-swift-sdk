//
//  QueueProcessorTests.swift
//  KlaviyoCoreTests
//
//  Created by Claude Code on 2025-11-10.
//

@testable import KlaviyoCore
import XCTest

final class QueueProcessorTests: XCTestCase {
    var processor: QueueProcessor!
    var queue: RequestQueue!
    var persistence: QueuePersistence!
    var mockAPI: MockKlaviyoAPI!
    var testFileClient: TestFileClient!
    var config: QueueConfiguration!

    override func setUp() async throws {
        config = .test
        queue = RequestQueue(configuration: config)
        testFileClient = TestFileClient()
        persistence = QueuePersistence(
            fileClient: testFileClient,
            apiKey: "test-key"
        )
        mockAPI = MockKlaviyoAPI()
        processor = QueueProcessor(
            queue: queue,
            persistence: persistence,
            api: mockAPI,
            configuration: config
        )
    }

    override func tearDown() async throws {
        await processor.stop()
        await queue.clear()
        try? persistence.clear()
        processor = nil
        queue = nil
        mockAPI = nil
    }

    // MARK: - Start/Stop Tests

    func testStartEnablesProcessing() async {
        await processor.start()
        let isProcessing = await processor.isProcessing()
        XCTAssertTrue(isProcessing)
    }

    func testStopDisablesProcessing() async {
        await processor.start()
        await processor.stop()
        let isProcessing = await processor.isProcessing()
        XCTAssertFalse(isProcessing)
    }

    func testPauseStopsProcessing() async {
        await processor.start()
        await processor.pause()
        let isPaused = await processor.isCurrentlyPaused()
        XCTAssertTrue(isPaused)
    }

    func testResumeAfterPause() async {
        await processor.start()
        await processor.pause()
        await processor.resume()

        let isPaused = await processor.isCurrentlyPaused()
        let isProcessing = await processor.isProcessing()
        XCTAssertFalse(isPaused)
        XCTAssertTrue(isProcessing)
    }

    // MARK: - Success Flow Tests

    func testProcessSingleRequestSuccess() async throws {
        // Set up mock to succeed
        mockAPI.result = .success(Data())

        // Enqueue request
        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)

        // Start processor
        await processor.start()

        // Wait for processing (flush processes immediately)
        await processor.flush()

        // Verify request was processed and removed
        let queueCount = await queue.count
        XCTAssertEqual(queueCount, 0)
        XCTAssertEqual(mockAPI.sendCallCount, 1)
    }

    func testProcessMultipleRequestsSequentially() async throws {
        mockAPI.result = .success(Data())

        // Enqueue multiple requests
        await queue.enqueue(makeTestRequest(id: "1"), priority: .normal)
        await queue.enqueue(makeTestRequest(id: "2"), priority: .normal)
        await queue.enqueue(makeTestRequest(id: "3"), priority: .normal)

        await processor.start()
        await processor.flush()

        let queueCount = await queue.count
        XCTAssertEqual(queueCount, 0)
        XCTAssertEqual(mockAPI.sendCallCount, 3)
    }

    // MARK: - Failure Flow Tests

    func testNetworkErrorTriggersRetry() async throws {
        mockAPI.result = .failure(.networkError(URLError(.notConnectedToInternet)))

        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)

        await processor.start()
        await processor.flush()

        // Request should still be in queue with incremented retry
        let normalQueue = await queue.getNormalQueue()
        XCTAssertEqual(normalQueue.count, 1)
        XCTAssertEqual(normalQueue.first?.retryCount, 1)
    }

    func testRateLimitSetsBackoff() async throws {
        mockAPI.result = .failure(.rateLimitError(backOff: 10))

        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)

        await processor.start()
        await processor.flush()

        // Request should be in queue with backoff set
        let normalQueue = await queue.getNormalQueue()
        XCTAssertEqual(normalQueue.count, 1)
        XCTAssertNotNil(normalQueue.first?.backoffUntil)
        XCTAssertEqual(normalQueue.first?.retryCount, 1)
    }

    func testHTTP4xxErrorDropsRequest() async throws {
        mockAPI.result = .failure(.httpError(400, Data()))

        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)

        await processor.start()
        await processor.flush()

        // Request should be dropped
        let queueCount = await queue.count
        XCTAssertEqual(queueCount, 0)
    }

    func testHTTP5xxErrorTriggersRetry() async throws {
        mockAPI.result = .failure(.httpError(500, Data()))

        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)

        await processor.start()
        await processor.flush()

        // Request should be retried
        let normalQueue = await queue.getNormalQueue()
        XCTAssertEqual(normalQueue.count, 1)
        XCTAssertEqual(normalQueue.first?.retryCount, 1)
    }

    func testInternalErrorDropsRequest() async throws {
        mockAPI.result = .failure(.internalError("test error"))

        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)

        await processor.start()
        await processor.flush()

        // Request should be dropped
        let queueCount = await queue.count
        XCTAssertEqual(queueCount, 0)
    }

    // MARK: - Max Retries Tests

    func testMaxRetriesDropsRequest() async throws {
        mockAPI.result = .failure(.networkError(URLError(.timedOut)))

        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)

        await processor.start()

        // Process until max retries exceeded
        for _ in 0...config.maxRetries {
            await processor.flush()
        }

        // Request should eventually be dropped
        let queueCount = await queue.count
        XCTAssertEqual(queueCount, 0)
    }

    // MARK: - Priority Tests

    func testImmediatePriorityProcessedFirst() async throws {
        mockAPI.result = .success(Data())

        // Enqueue normal first, then immediate
        await queue.enqueue(makeTestRequest(id: "normal"), priority: .normal)
        await queue.enqueue(makeTestRequest(id: "immediate"), priority: .immediate)

        await processor.start()

        // Wait briefly for first request to be processed
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Immediate should have been processed first
        XCTAssertEqual(mockAPI.lastProcessedRequestId, "immediate")
    }

    // MARK: - Persistence Tests

    func testProcessingPersistsQueueState() async throws {
        mockAPI.result = .success(Data())

        await queue.enqueue(makeTestRequest(), priority: .normal)
        await processor.start()
        await processor.flush()

        // Verify persistence was called (queue should be empty now)
        XCTAssertGreaterThan(testFileClient.writtenFiles.count, 0)
    }

    func testFailurePersistsUpdatedRetryState() async throws {
        mockAPI.result = .failure(.networkError(URLError(.notConnectedToInternet)))

        await queue.enqueue(makeTestRequest(), priority: .normal)
        await processor.start()
        await processor.flush()

        // Load persisted state
        let (_, normal) = persistence.load()
        XCTAssertEqual(normal.count, 1)
        XCTAssertEqual(normal.first?.retryCount, 1)
    }

    // MARK: - Backoff Tests

    func testBackoffPreventsImmediateReprocessing() async throws {
        var callCount = 0
        mockAPI.customHandler = { _, _ in
            callCount += 1
            return .failure(.rateLimitError(backOff: 5))
        }

        await queue.enqueue(makeTestRequest(), priority: .normal)
        await processor.start()

        // First flush will fail with rate limit
        await processor.flush()
        XCTAssertEqual(callCount, 1)

        // Second flush should skip due to backoff
        await processor.flush()
        XCTAssertEqual(callCount, 1, "Should not retry during backoff")
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

// MARK: - Mock API

class MockKlaviyoAPI: KlaviyoAPI {
    var result: Result<Data, KlaviyoAPIError> = .success(Data())
    var sendCallCount = 0
    var lastProcessedRequestId: String?
    var customHandler: ((KlaviyoRequest, RequestAttemptInfo) async -> Result<Data, KlaviyoAPIError>)?

    init() {
        super.init(send: { _, _ in .success(Data()) })
        send = { [weak self] request, attemptInfo in
            guard let self = self else { return .success(Data()) }
            self.sendCallCount += 1
            self.lastProcessedRequestId = request.id

            if let handler = self.customHandler {
                return await handler(request, attemptInfo)
            }

            return self.result
        }
    }
}
