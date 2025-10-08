//
//  EventBuffer.swift
//  klaviyo-swift-sdk
//
//  Created by Ajay Subramanya on 10/7/25.
//

import Combine
import Foundation
import KlaviyoCore
import OSLog

// MARK: - Logger

@available(iOS 14.0, *)
extension Logger {
    fileprivate static let eventBuffer = Logger(subsystem: "com.klaviyo.klaviyo-swift-sdk.klaviyoSwift", category: "Event Buffering")
}

/// Manages a thread-safe buffer of recent events for replay to new subscribers.
/// This handles race conditions where events may be published before subscribers exist.
final class EventBuffer {
    // MARK: - Properties

    private struct BufferedEvent {
        let event: Event
        let timestamp: Date
    }

    private var buffer: [BufferedEvent] = []
    private let maxBufferSize: Int
    private let maxBufferAge: TimeInterval
    private let queue = DispatchQueue(label: "com.klaviyo.eventBuffer", attributes: .concurrent)

    // MARK: - Initialization

    /// Creates a new event buffer with specified limits.
    /// - Parameters:
    ///   - maxBufferSize: Maximum number of events to keep (default: 10)
    ///   - maxBufferAge: Maximum age of events to keep in seconds (default: 10)
    init(maxBufferSize: Int = 10, maxBufferAge: TimeInterval = 10) {
        self.maxBufferSize = maxBufferSize
        self.maxBufferAge = maxBufferAge
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
            let now = Date()

            // Clean old events from buffer
            self.buffer = self.buffer.filter { now.timeIntervalSince($0.timestamp) < self.maxBufferAge }

            // Add new event
            self.buffer.append(BufferedEvent(event: event, timestamp: now))

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
            let now = Date()
            let recentEvents = buffer
                .filter { now.timeIntervalSince($0.timestamp) < maxBufferAge }
                .map(\.event)

            if #available(iOS 14.0, *) {
                if recentEvents.isEmpty {
                    Logger.eventBuffer.info("📭 Event buffer is empty - no events to replay")
                } else {
                    Logger.eventBuffer.info("📬 Replaying \(recentEvents.count) buffered event(s): \(recentEvents.map(\.metric.name.value).joined(separator: ", "), privacy: .public)")
                }
            }

            return recentEvents
        }
    }

    /// Clears all buffered events.
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.buffer.removeAll()

            if #available(iOS 14.0, *) {
                Logger.eventBuffer.info("🗑️ Cleared event buffer")
            }
        }
    }
}
