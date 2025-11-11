//
//  RequestQueueTests.swift
//  KlaviyoCoreTests
//
//  Created by Claude Code on 2025-11-10.
//

@testable import KlaviyoCore
import XCTest

final class RequestQueueTests: XCTestCase {
    var queue: RequestQueue!
    var config: QueueConfiguration!

    override func setUp() async throws {
        config = .test
        queue = RequestQueue(configuration: config)
    }

    override func tearDown() async throws {
        await queue.clear()
        queue = nil
    }

    // MARK: - Basic Enqueue/Dequeue Tests

    func testEnqueueNormalPriority() async {
        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)

        let count = await queue.count
        XCTAssertEqual(count, 1)
    }

    func testEnqueueImmediatePriority() async {
        let request = makeTestRequest()
        await queue.enqueue(request, priority: .immediate)

        let count = await queue.count
        XCTAssertEqual(count, 1)
    }

    func testDequeueEmptyQueue() async {
        let result = await queue.dequeue()
        XCTAssertNil(result)
    }

    func testDequeueNormalPriority() async {
        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)

        let dequeued = await queue.dequeue()
        XCTAssertNotNil(dequeued)
        XCTAssertEqual(dequeued?.request.id, request.id)
    }

    func testDequeueImmediatePriority() async {
        let request = makeTestRequest()
        await queue.enqueue(request, priority: .immediate)

        let dequeued = await queue.dequeue()
        XCTAssertNotNil(dequeued)
        XCTAssertEqual(dequeued?.request.id, request.id)
    }

    // MARK: - Priority Tests

    func testImmediatePriorityProcessedFirst() async {
        let normalRequest = makeTestRequest(id: "normal")
        let immediateRequest = makeTestRequest(id: "immediate")

        // Enqueue normal first, then immediate
        await queue.enqueue(normalRequest, priority: .normal)
        await queue.enqueue(immediateRequest, priority: .immediate)

        // Dequeue should return immediate first
        let first = await queue.dequeue()
        XCTAssertEqual(first?.request.id, "immediate")

        let second = await queue.dequeue()
        XCTAssertEqual(second?.request.id, "normal")
    }

    func testMultipleImmediatePriorityFIFO() async {
        let request1 = makeTestRequest(id: "immediate1")
        let request2 = makeTestRequest(id: "immediate2")
        let request3 = makeTestRequest(id: "immediate3")

        await queue.enqueue(request1, priority: .immediate)
        await queue.enqueue(request2, priority: .immediate)
        await queue.enqueue(request3, priority: .immediate)

        let first = await queue.dequeue()
        XCTAssertEqual(first?.request.id, "immediate1")

        let second = await queue.dequeue()
        XCTAssertEqual(second?.request.id, "immediate2")

        let third = await queue.dequeue()
        XCTAssertEqual(third?.request.id, "immediate3")
    }

    func testMultipleNormalPriorityFIFO() async {
        let request1 = makeTestRequest(id: "normal1")
        let request2 = makeTestRequest(id: "normal2")
        let request3 = makeTestRequest(id: "normal3")

        await queue.enqueue(request1, priority: .normal)
        await queue.enqueue(request2, priority: .normal)
        await queue.enqueue(request3, priority: .normal)

        let first = await queue.dequeue()
        XCTAssertEqual(first?.request.id, "normal1")

        let second = await queue.dequeue()
        XCTAssertEqual(second?.request.id, "normal2")

        let third = await queue.dequeue()
        XCTAssertEqual(third?.request.id, "normal3")
    }

    // MARK: - Max Queue Size Tests

    func testNormalQueueEnforcesMaxSize() async {
        // Config has maxQueueSize = 10
        for i in 0..<15 {
            let request = makeTestRequest(id: "request\(i)")
            await queue.enqueue(request, priority: .normal)
        }

        let count = await queue.count
        XCTAssertEqual(count, 10, "Queue should be capped at max size")

        // First 5 should have been dropped (oldest)
        let first = await queue.dequeue()
        XCTAssertEqual(first?.request.id, "request5", "Oldest requests should be dropped")
    }

    func testImmediateQueueNotAffectedByMaxSize() async {
        // Immediate queue has no size limit
        for i in 0..<15 {
            let request = makeTestRequest(id: "immediate\(i)")
            await queue.enqueue(request, priority: .immediate)
        }

        let immediateQueue = await queue.getImmediateQueue()
        XCTAssertEqual(immediateQueue.count, 15, "Immediate queue should not be capped")
    }

    // MARK: - In-Flight Tests

    func testDequeueMarksAsInFlight() async {
        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)

        await queue.dequeue()

        let inFlight = await queue.getInFlight()
        XCTAssertTrue(inFlight.contains(request.id))
    }

    func testCannotEnqueueInFlightRequest() async {
        let request = makeTestRequest(id: "duplicate")
        await queue.enqueue(request, priority: .normal)
        await queue.dequeue()

        // Try to enqueue same request again
        await queue.enqueue(request, priority: .normal)

        let count = await queue.count
        XCTAssertEqual(count, 0, "Should not enqueue duplicate in-flight request")
    }

    func testCannotDequeueInFlightRequest() async {
        let request1 = makeTestRequest(id: "request1")
        let request2 = makeTestRequest(id: "request2")

        await queue.enqueue(request1, priority: .normal)
        await queue.enqueue(request2, priority: .normal)

        // Dequeue first request (now in-flight)
        let first = await queue.dequeue()
        XCTAssertEqual(first?.request.id, "request1")

        // Dequeue again should skip in-flight and return second
        let second = await queue.dequeue()
        XCTAssertEqual(second?.request.id, "request2")
    }

    // MARK: - Complete/Fail Tests

    func testCompleteRemovesFromQueue() async {
        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)
        await queue.dequeue()

        await queue.complete(request.id)

        let count = await queue.count
        let inFlight = await queue.getInFlight()
        XCTAssertEqual(count, 0)
        XCTAssertFalse(inFlight.contains(request.id))
    }

    func testFailWithRetryKeepsInQueue() async {
        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)
        let dequeued = await queue.dequeue()!

        let updated = dequeued.withIncrementedRetry()
        await queue.fail(request.id, shouldRetry: true, updatedRequest: updated)

        let normalQueue = await queue.getNormalQueue()
        XCTAssertEqual(normalQueue.count, 1)
        XCTAssertEqual(normalQueue.first?.retryCount, 1)

        let inFlight = await queue.getInFlight()
        XCTAssertFalse(inFlight.contains(request.id), "Should remove from in-flight")
    }

    func testFailWithoutRetryRemovesFromQueue() async {
        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)
        await queue.dequeue()

        await queue.fail(request.id, shouldRetry: false)

        let count = await queue.count
        let inFlight = await queue.getInFlight()
        XCTAssertEqual(count, 0)
        XCTAssertFalse(inFlight.contains(request.id))
    }

    // MARK: - Backoff Tests

    func testBackoffPreventsDequeue() async {
        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)
        let dequeued = await queue.dequeue()!

        // Set backoff to 10 seconds in future
        let backoffUntil = environment.date().addingTimeInterval(10)
        let updated = dequeued.withBackoff(until: backoffUntil)
        await queue.fail(request.id, shouldRetry: true, updatedRequest: updated)

        // Try to dequeue immediately - should be nil due to backoff
        let result = await queue.dequeue()
        XCTAssertNil(result, "Request should not be dequeued during backoff")

        let count = await queue.count
        XCTAssertEqual(count, 1, "Request should still be in queue")
    }

    func testBackoffExpiresAllowsDequeue() async {
        // Override date to control time
        var currentDate = Date()
        environment.date = { currentDate }

        let request = makeTestRequest()
        await queue.enqueue(request, priority: .normal)
        let dequeued = await queue.dequeue()!

        // Set backoff to 1 second in future
        let backoffUntil = currentDate.addingTimeInterval(1)
        let updated = dequeued.withBackoff(until: backoffUntil)
        await queue.fail(request.id, shouldRetry: true, updatedRequest: updated)

        // Advance time past backoff
        currentDate = currentDate.addingTimeInterval(2)

        // Should now be dequeueable
        let result = await queue.dequeue()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.request.id, request.id)
    }

    // MARK: - Persistence Helper Tests

    func testAllRequestsReturnsAllQueues() async {
        let immediate1 = makeTestRequest(id: "immediate1")
        let immediate2 = makeTestRequest(id: "immediate2")
        let normal1 = makeTestRequest(id: "normal1")
        let normal2 = makeTestRequest(id: "normal2")

        await queue.enqueue(immediate1, priority: .immediate)
        await queue.enqueue(immediate2, priority: .immediate)
        await queue.enqueue(normal1, priority: .normal)
        await queue.enqueue(normal2, priority: .normal)

        let (immediate, normal) = await queue.allRequests()
        XCTAssertEqual(immediate.count, 2)
        XCTAssertEqual(normal.count, 2)
    }

    func testRestoreLoadsQueues() async {
        let immediate = [
            QueuedRequest(request: makeTestRequest(id: "immediate1"), retryCount: 1),
            QueuedRequest(request: makeTestRequest(id: "immediate2"), retryCount: 0)
        ]
        let normal = [
            QueuedRequest(request: makeTestRequest(id: "normal1"), retryCount: 2),
            QueuedRequest(request: makeTestRequest(id: "normal2"), retryCount: 0)
        ]

        await queue.restore(immediate: immediate, normal: normal)

        let count = await queue.count
        XCTAssertEqual(count, 4)

        let immediateQueue = await queue.getImmediateQueue()
        let normalQueue = await queue.getNormalQueue()
        XCTAssertEqual(immediateQueue.count, 2)
        XCTAssertEqual(normalQueue.count, 2)
        XCTAssertEqual(immediateQueue.first?.retryCount, 1)
        XCTAssertEqual(normalQueue.first?.retryCount, 2)
    }

    func testClearRemovesAllRequests() async {
        await queue.enqueue(makeTestRequest(), priority: .immediate)
        await queue.enqueue(makeTestRequest(), priority: .normal)
        await queue.dequeue()

        await queue.clear()

        let count = await queue.count
        let inFlight = await queue.getInFlight()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(inFlight.count, 0)
    }

    func testIsEmpty() async {
        let isEmpty = await queue.isEmpty
        XCTAssertTrue(isEmpty)

        await queue.enqueue(makeTestRequest(), priority: .normal)
        let isEmptyAfter = await queue.isEmpty
        XCTAssertFalse(isEmptyAfter)
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
