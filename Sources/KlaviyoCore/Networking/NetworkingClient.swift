//
//  NetworkingClient.swift
//  KlaviyoCore
//
//  Created by Claude Code on 2025-11-10.
//

import Foundation

/// Public API for network operations and request queueing
public class NetworkingClient {
    /// Shared singleton instance
    public static var shared: NetworkingClient?

    /// Request queue
    private let queue: RequestQueue

    /// Queue processor
    private let processor: QueueProcessor

    /// Persistence handler
    private let persistence: QueuePersistence

    /// API client for direct sends
    private let api: KlaviyoAPI

    /// Configuration
    private let configuration: QueueConfiguration

    /// Initialize networking client
    /// - Parameters:
    ///   - apiKey: Klaviyo API key
    ///   - configuration: Queue configuration (default: .default)
    public init(
        apiKey: String,
        configuration: QueueConfiguration = .default
    ) {
        self.configuration = configuration
        queue = RequestQueue(configuration: configuration)
        persistence = QueuePersistence(apiKey: apiKey)
        api = environment.apiClient()
        processor = QueueProcessor(
            queue: queue,
            persistence: persistence,
            api: api,
            configuration: configuration
        )

        // Load persisted queue
        let (immediate, normal) = persistence.load()
        Task {
            await queue.restore(immediate: immediate, normal: normal)
        }
    }

    // MARK: - Public API

    /// Send a request immediately, bypassing the queue
    /// This is for time-critical operations like geofence events
    /// - Parameter request: The request to send
    /// - Returns: Response data on success
    /// - Throws: KlaviyoAPIError on failure
    public func send(_ request: KlaviyoRequest) async throws -> Data {
        let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 1)
        let result = await api.send(request, attemptInfo)

        switch result {
        case let .success(data):
            return data
        case let .failure(error):
            throw error
        }
    }

    /// Enqueue a request for later processing
    /// This is a fire-and-forget operation - errors are logged but not returned
    /// - Parameters:
    ///   - request: The request to enqueue
    ///   - priority: Queue priority (default: .normal)
    public func enqueue(_ request: KlaviyoRequest, priority: RequestPriority = .normal) {
        Task {
            await queue.enqueue(request, priority: priority)
            // Persist queue state
            let (immediate, normal) = await queue.allRequests()
            try? persistence.save(immediate: immediate, normal: normal)
        }
    }

    /// Start processing queued requests
    /// This is called automatically on initialization, but can be called manually if stopped
    public func start() {
        Task {
            await processor.start()
        }
    }

    /// Pause processing (e.g., on app background)
    /// Queue remains intact and persisted
    public func pause() {
        Task {
            await processor.pause()
            // Persist current state
            let (immediate, normal) = await queue.allRequests()
            try? persistence.save(immediate: immediate, normal: normal)
        }
    }

    /// Resume processing after pause
    public func resume() {
        Task {
            await processor.resume()
        }
    }

    /// Stop processing completely
    public func stop() {
        Task {
            await processor.stop()
        }
    }

    /// Flush queue immediately - process all pending requests
    public func flush() async {
        await processor.flush()
    }

    // MARK: - State Access (for debugging/testing)

    /// Get current queue count
    public func queueCount() async -> Int {
        await queue.count
    }

    /// Get in-flight request count
    public func inFlightCount() async -> Int {
        await queue.inFlightCount
    }

    /// Check if queue is empty
    public func isEmpty() async -> Bool {
        await queue.isEmpty
    }

    /// Clear all queued requests (use with caution)
    public func clearQueue() async {
        await queue.clear()
        try? persistence.clear()
    }

    // MARK: - Singleton Configuration

    /// Configure the shared singleton instance
    /// This must be called before accessing .shared
    /// - Parameters:
    ///   - apiKey: Klaviyo API key
    ///   - configuration: Queue configuration (default: .default)
    public static func configure(apiKey: String, configuration: QueueConfiguration = .default) {
        shared = NetworkingClient(apiKey: apiKey, configuration: configuration)
        shared?.start()
    }

    /// Deconfigure the shared singleton (for testing)
    public static func reset() {
        shared?.stop()
        shared = nil
    }
}
