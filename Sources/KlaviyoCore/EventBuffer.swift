//
//  EventBuffer.swift
//  klaviyo-swift-sdk
//
//  Created by Ajay Subramanya on 10/7/25.
//

import Combine
import Foundation
import OSLog

// MARK: - Logger

@available(iOS 14.0, *)
extension Logger {
    fileprivate static let eventBuffer = Logger(
        subsystem: "com.klaviyo.klaviyo-swift-sdk.klaviyoCore",
        category: "Event Buffering"
    )
}

/// Manages a thread-safe buffer of recent events for replay to new subscribers.
/// This handles race conditions where events may be published before subscribers exist.
final class EventBuffer {
    // MARK: - Properties

    private struct BufferedEvent {
        let event: Event
        let timestamp: TimeInterval // systemUptime (monotonic clock)
    }

    private var buffer: [BufferedEvent] = []
    private let maxBufferSize: Int
    private let maxBufferAge: TimeInterval
    private let clock: () -> TimeInterval
    private let queue = DispatchQueue(label: "com.klaviyo.eventBuffer", attributes: .concurrent)

    // MARK: - Initialization

    /// Creates a new event buffer with specified limits.
    /// - Parameters:
    ///   - maxBufferSize: Maximum number of events to keep (default: 10)
    ///   - maxBufferAge: Maximum age of events to keep in seconds (default: 10)
    ///   - clock: Monotonic clock source. Injectable so tests can advance time deterministically;
    ///     defaults to `ProcessInfo.processInfo.systemUptime`.
    init(
        maxBufferSize: Int = 10,
        maxBufferAge: TimeInterval = 10,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.maxBufferSize = maxBufferSize
        self.maxBufferAge = maxBufferAge
        self.clock = clock
    }

    // MARK: - Public Methods

    /// Adds an event to the buffer, maintaining size and age limits.
    /// - Parameter event: The event to buffer
    func buffer(_ event: Event) {
        if #available(iOS 14.0, *) {
            Logger.eventBuffer.info("📤 Buffering event: \(event.metric.name.value, privacy: .public)")
        }

        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            let currentTime = self.clock()

            // Clean old events from buffer (using monotonic clock to avoid issues with device clock changes)
            self.buffer = self.buffer.filter { currentTime - $0.timestamp < self.maxBufferAge }

            // Add new event
            self.buffer.append(BufferedEvent(event: event, timestamp: currentTime))

            // Keep only last N events
            if self.buffer.count > self.maxBufferSize {
                self.buffer = Array(self.buffer.suffix(self.maxBufferSize))
            }

            if #available(iOS 14.0, *) {
                Logger.eventBuffer.info("💾 Buffer now has \(self.buffer.count) event(s)")
            }
        }
    }

    /// Gets recent events from the buffer (within maxBufferAge).
    /// - Returns: Array of buffered events that haven't expired
    func getRecentEvents() -> [Event] {
        queue.sync {
            let currentTime = clock()
            let recentEvents = buffer
                .filter { currentTime - $0.timestamp < maxBufferAge }
                .map(\.event)

            if #available(iOS 14.0, *) {
                if recentEvents.isEmpty {
                    Logger.eventBuffer.info("📭 Event buffer is empty - no events to replay")
                } else {
                    let names = recentEvents.map(\.metric.name.value).joined(separator: ", ")
                    Logger.eventBuffer.info(
                        "📬 Replaying \(recentEvents.count) buffered event(s): \(names, privacy: .public)"
                    )
                }
            }

            return recentEvents
        }
    }

    /// Clears all events from the buffer.
    /// This is useful for testing to ensure clean state between tests.
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.buffer.removeAll()
        }
    }
}
