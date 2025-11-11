//
//  RequestQueue.swift
//  KlaviyoCore
//
//  Created by Claude Code on 2025-11-10.
//

import Foundation

/// Priority level for queued requests
public enum RequestPriority: String, Codable, Sendable {
    /// Immediate priority - processed before normal requests
    case immediate
    /// Normal priority - standard FIFO processing
    case normal
}

/// Thread-safe queue for managing Klaviyo requests with priority support
actor RequestQueue {
    /// Configuration for queue behavior
    private let configuration: QueueConfiguration

    /// High-priority requests (processed first)
    private var immediateQueue: [QueuedRequest] = []

    /// Normal-priority requests (processed after immediate)
    private var normalQueue: [QueuedRequest] = []

    /// Set of request IDs currently being processed
    private var inFlight: Set<String> = []

    /// Initialize queue with configuration
    /// - Parameter configuration: Queue configuration (default: .default)
    init(configuration: QueueConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Enqueue a request for processing
    /// - Parameters:
    ///   - request: The request to enqueue
    ///   - priority: Priority level (default: .normal)
    func enqueue(_ request: KlaviyoRequest, priority: RequestPriority = .normal) {
        let queuedRequest = QueuedRequest(request: request)

        // Don't enqueue if already in flight or already queued
        guard !inFlight.contains(request.id),
              !contains(requestId: request.id) else {
            return
        }

        switch priority {
        case .immediate:
            immediateQueue.append(queuedRequest)
        case .normal:
            // Enforce max queue size for normal queue
            if normalQueue.count >= configuration.maxQueueSize {
                // Drop oldest request to make room
                normalQueue.removeFirst()
            }
            normalQueue.append(queuedRequest)
        }
    }

    /// Dequeue the next ready request (immediate priority first, then normal)
    /// - Returns: The next ready request, or nil if queue is empty or all requests are in backoff
    func dequeue() -> QueuedRequest? {
        let now = environment.date()

        // Try immediate queue first
        if let index = immediateQueue.firstIndex(where: { !inFlight.contains($0.id) && $0.isReadyToProcess(at: now) }) {
            let request = immediateQueue[index]
            inFlight.insert(request.id)
            return request
        }

        // Then try normal queue
        if let index = normalQueue.firstIndex(where: { !inFlight.contains($0.id) && $0.isReadyToProcess(at: now) }) {
            let request = normalQueue[index]
            inFlight.insert(request.id)
            return request
        }

        return nil
    }

    /// Mark a request as completed and remove it from the queue
    /// - Parameter requestId: The ID of the completed request
    func complete(_ requestId: String) {
        inFlight.remove(requestId)
        removeFromQueues(requestId: requestId)
    }

    /// Handle a failed request - either re-queue with updated retry state or drop
    /// - Parameters:
    ///   - requestId: The ID of the failed request
    ///   - shouldRetry: Whether to re-queue the request
    ///   - updatedRequest: The updated request with new retry state (if retrying)
    func fail(_ requestId: String, shouldRetry: Bool, updatedRequest: QueuedRequest? = nil) {
        inFlight.remove(requestId)

        if shouldRetry, let updated = updatedRequest {
            // Update the request in the appropriate queue
            if let index = immediateQueue.firstIndex(where: { $0.id == requestId }) {
                immediateQueue[index] = updated
            } else if let index = normalQueue.firstIndex(where: { $0.id == requestId }) {
                normalQueue[index] = updated
            }
        } else {
            // Drop the request
            removeFromQueues(requestId: requestId)
        }
    }

    /// Get total count of requests (including in-flight)
    var count: Int {
        immediateQueue.count + normalQueue.count
    }

    /// Check if queue is empty (excluding in-flight)
    var isEmpty: Bool {
        immediateQueue.isEmpty && normalQueue.isEmpty
    }

    /// Get count of in-flight requests
    var inFlightCount: Int {
        inFlight.count
    }

    /// Get all requests for persistence
    /// - Returns: Tuple of immediate and normal queue contents
    func allRequests() -> (immediate: [QueuedRequest], normal: [QueuedRequest]) {
        (immediate: immediateQueue, normal: normalQueue)
    }

    /// Restore queue from persisted state
    /// - Parameters:
    ///   - immediate: Immediate priority requests
    ///   - normal: Normal priority requests
    func restore(immediate: [QueuedRequest], normal: [QueuedRequest]) {
        immediateQueue = immediate
        normalQueue = normal
        inFlight.removeAll()
    }

    /// Clear all requests from the queue
    func clear() {
        immediateQueue.removeAll()
        normalQueue.removeAll()
        inFlight.removeAll()
    }

    // MARK: - Private Helpers

    /// Check if a request with the given ID exists in any queue
    private func contains(requestId: String) -> Bool {
        immediateQueue.contains(where: { $0.id == requestId }) ||
            normalQueue.contains(where: { $0.id == requestId })
    }

    /// Remove a request from all queues
    private func removeFromQueues(requestId: String) {
        immediateQueue.removeAll(where: { $0.id == requestId })
        normalQueue.removeAll(where: { $0.id == requestId })
    }
}

// MARK: - Debug/Testing Helpers

extension RequestQueue {
    /// Get immediate queue contents (for testing)
    func getImmediateQueue() -> [QueuedRequest] {
        immediateQueue
    }

    /// Get normal queue contents (for testing)
    func getNormalQueue() -> [QueuedRequest] {
        normalQueue
    }

    /// Get in-flight request IDs (for testing)
    func getInFlight() -> Set<String> {
        inFlight
    }
}
