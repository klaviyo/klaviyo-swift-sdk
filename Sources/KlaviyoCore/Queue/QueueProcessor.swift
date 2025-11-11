//
//  QueueProcessor.swift
//  KlaviyoCore
//
//  Created by Claude Code on 2025-11-10.
//

import Foundation

/// Actor responsible for processing queued requests
actor QueueProcessor {
    /// The request queue to process
    private let queue: RequestQueue

    /// Persistence handler for saving queue state
    private let persistence: QueuePersistence

    /// API client for executing requests
    private let api: KlaviyoAPI

    /// Configuration for queue behavior
    private let configuration: QueueConfiguration

    /// Whether the processor is currently running
    private var isRunning = false

    /// Whether the processor is paused
    private var isPaused = false

    /// Task handle for the processing loop
    private var processingTask: Task<Void, Never>?

    /// Initialize processor
    /// - Parameters:
    ///   - queue: The request queue to process
    ///   - persistence: Persistence handler
    ///   - api: API client (default: production)
    ///   - configuration: Queue configuration (default: .default)
    init(
        queue: RequestQueue,
        persistence: QueuePersistence,
        api: KlaviyoAPI = environment.apiClient(),
        configuration: QueueConfiguration = .default
    ) {
        self.queue = queue
        self.persistence = persistence
        self.api = api
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Start processing the queue
    func start() {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        startProcessingLoop()
    }

    /// Pause processing (queue remains intact)
    func pause() {
        isPaused = true
    }

    /// Resume processing after pause
    func resume() {
        guard isRunning else {
            start()
            return
        }
        isPaused = false
        // Processing loop will continue when it wakes up
    }

    /// Stop processing completely
    func stop() {
        isRunning = false
        isPaused = false
        processingTask?.cancel()
        processingTask = nil
    }

    /// Flush queue immediately (process all pending requests)
    func flush() async {
        guard isRunning, !isPaused else { return }
        // Process until queue is empty
        while await !queue.isEmpty {
            await processNext()
        }
    }

    // MARK: - Processing Loop

    /// Start the background processing loop
    private func startProcessingLoop() {
        processingTask?.cancel()
        processingTask = Task {
            await processLoop()
        }
    }

    /// Main processing loop
    private func processLoop() async {
        while isRunning {
            // Skip if paused
            guard !isPaused else {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                continue
            }

            // Try to process next request
            let processed = await processNext()

            // If nothing was processed, sleep briefly
            if !processed {
                let interval = UInt64(configuration.flushInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: interval)
            }

            // Check if task was cancelled
            if Task.isCancelled {
                break
            }
        }
    }

    /// Process the next request in the queue
    /// - Returns: True if a request was processed, false if queue was empty or no ready requests
    private func processNext() async -> Bool {
        // Dequeue next ready request
        guard let queuedRequest = await queue.dequeue() else {
            return false
        }

        // Execute the request
        let result = await execute(queuedRequest)

        // Handle result
        switch result {
        case .success:
            await handleSuccess(queuedRequest)
        case let .failure(error):
            await handleFailure(queuedRequest, error)
        }

        // Persist queue state after each operation
        await persistQueue()

        return true
    }

    // MARK: - Request Execution

    /// Execute a single request
    /// - Parameter queuedRequest: The request to execute
    /// - Returns: Result of the execution
    private func execute(_ queuedRequest: QueuedRequest) async -> Result<Data, KlaviyoAPIError> {
        let attemptInfo: RequestAttemptInfo
        do {
            attemptInfo = try RequestAttemptInfo(
                attemptNumber: queuedRequest.retryCount + 1,
                maxAttempts: configuration.maxRetries
            )
        } catch {
            environment.logger.error("Failed to create attempt info: \(error)")
            return .failure(.internalError("Invalid attempt info"))
        }

        return await api.send(queuedRequest.request, attemptInfo)
    }

    // MARK: - Success/Failure Handling

    /// Handle successful request execution
    private func handleSuccess(_ queuedRequest: QueuedRequest) async {
        await queue.complete(queuedRequest.id)
    }

    /// Handle failed request execution
    private func handleFailure(_ queuedRequest: QueuedRequest, _ error: KlaviyoAPIError) async {
        let shouldRetry: Bool
        let updatedRequest: QueuedRequest?

        switch error {
        case .networkError:
            // Network errors are retryable
            (shouldRetry, updatedRequest) = await handleRetryableError(queuedRequest)

        case let .rateLimitError(backOff: backoff):
            // Rate limit errors need backoff
            (shouldRetry, updatedRequest) = await handleRateLimitError(queuedRequest, backoff: backoff)

        case let .httpError(statusCode, data):
            // HTTP errors - only 4xx are non-retryable
            if (400..<500).contains(statusCode) {
                // Client error - drop request
                (shouldRetry, updatedRequest) = (false, nil)
                environment.logger.warning("Dropping request \(queuedRequest.id) due to client error: \(statusCode)")
                // TODO: Parse response and handle invalid fields (email/phone)
            } else {
                // Server error - retry
                (shouldRetry, updatedRequest) = await handleRetryableError(queuedRequest)
            }

        case .missingOrInvalidResponse,
             .internalError,
             .internalRequestError,
             .unknownError,
             .dataEncodingError,
             .invalidData:
            // Internal errors - drop request
            (shouldRetry, updatedRequest) = (false, nil)
            environment.logger.error("Dropping request \(queuedRequest.id) due to internal error: \(error)")
        }

        await queue.fail(queuedRequest.id, shouldRetry: shouldRetry, updatedRequest: updatedRequest)
    }

    /// Handle a retryable error (network, server error, etc.)
    /// - Parameter queuedRequest: The failed request
    /// - Returns: Tuple of (shouldRetry, updatedRequest)
    private func handleRetryableError(_ queuedRequest: QueuedRequest) async -> (Bool, QueuedRequest?) {
        let newRetryCount = queuedRequest.retryCount + 1

        // Check if max retries exceeded
        guard newRetryCount <= configuration.maxRetries else {
            environment.logger.warning("Dropping request \(queuedRequest.id) - max retries (\(configuration.maxRetries)) exceeded")
            return (false, nil)
        }

        // Increment retry count and re-queue
        let updated = queuedRequest.withIncrementedRetry()
        return (true, updated)
    }

    /// Handle a rate limit error with backoff
    /// - Parameters:
    ///   - queuedRequest: The failed request
    ///   - backoff: Backoff duration in seconds
    /// - Returns: Tuple of (shouldRetry, updatedRequest)
    private func handleRateLimitError(_ queuedRequest: QueuedRequest, backoff: Int) async -> (Bool, QueuedRequest?) {
        let newRetryCount = queuedRequest.retryCount + 1

        // Check if max retries exceeded
        guard newRetryCount <= configuration.maxRetries else {
            environment.logger.warning("Dropping request \(queuedRequest.id) - max retries (\(configuration.maxRetries)) exceeded")
            return (false, nil)
        }

        // Calculate backoff time (capped at maxBackoff)
        let cappedBackoff = min(Double(backoff), configuration.maxBackoff)
        let backoffUntil = environment.date().addingTimeInterval(cappedBackoff)

        // Update request with backoff and incremented retry
        let updated = queuedRequest
            .withIncrementedRetry()
            .withBackoff(until: backoffUntil)

        environment.logger.info("Rate limited request \(queuedRequest.id) - backing off for \(cappedBackoff)s until \(backoffUntil)")

        return (true, updated)
    }

    // MARK: - Persistence

    /// Persist current queue state
    private func persistQueue() async {
        let (immediate, normal) = await queue.allRequests()
        do {
            try persistence.save(immediate: immediate, normal: normal)
        } catch {
            environment.logger.error("Failed to persist queue: \(error)")
        }
    }

    // MARK: - Testing Helpers

    /// Get processing state (for testing)
    func isProcessing() -> Bool {
        isRunning && !isPaused
    }

    /// Get paused state (for testing)
    func isCurrentlyPaused() -> Bool {
        isPaused
    }
}
