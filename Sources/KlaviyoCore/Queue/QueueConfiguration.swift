//
//  QueueConfiguration.swift
//  KlaviyoCore
//
//  Created by Claude Code on 2025-11-10.
//

import Foundation

/// Configuration for queue behavior
public struct QueueConfiguration: Equatable, Sendable {
    /// Maximum requests in normal queue before dropping oldest
    public let maxQueueSize: Int

    /// Maximum retry attempts per request before dropping
    public let maxRetries: Int

    /// Interval between queue processing attempts (seconds)
    public let flushInterval: TimeInterval

    /// Maximum backoff duration for rate limiting (seconds)
    public let maxBackoff: TimeInterval

    /// Minimum backoff duration for rate limiting (seconds)
    public let minBackoff: TimeInterval

    /// Jitter range for backoff randomization (seconds)
    public let jitterRange: ClosedRange<Int>

    /// Initialize with custom configuration
    /// - Parameters:
    ///   - maxQueueSize: Maximum requests in normal queue (default: 200)
    ///   - maxRetries: Maximum retry attempts (default: 50)
    ///   - flushInterval: Processing interval in seconds (default: 10.0)
    ///   - maxBackoff: Maximum backoff in seconds (default: 180.0)
    ///   - minBackoff: Minimum backoff in seconds (default: 1.0)
    ///   - jitterRange: Range for random jitter (default: 0...9)
    public init(
        maxQueueSize: Int = 200,
        maxRetries: Int = 50,
        flushInterval: TimeInterval = 10.0,
        maxBackoff: TimeInterval = 180.0,
        minBackoff: TimeInterval = 1.0,
        jitterRange: ClosedRange<Int> = 0...9
    ) {
        self.maxQueueSize = maxQueueSize
        self.maxRetries = maxRetries
        self.flushInterval = flushInterval
        self.maxBackoff = maxBackoff
        self.minBackoff = minBackoff
        self.jitterRange = jitterRange
    }

    /// Default configuration matching existing KlaviyoSwift behavior
    public static let `default` = QueueConfiguration()

    /// Test configuration with shorter intervals for faster testing
    public static let test = QueueConfiguration(
        maxQueueSize: 10,
        maxRetries: 3,
        flushInterval: 0.1,
        maxBackoff: 5.0,
        minBackoff: 0.1,
        jitterRange: 0...1
    )
}
