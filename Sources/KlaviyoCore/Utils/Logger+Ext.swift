//
//  Logger+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 7/25/25.
//

import Foundation
import OSLog

// MARK: - Logging Configuration

/// Thread-safe global logging toggle for the Klaviyo SDK.
///
/// When logging is disabled, all `Logger` instances across every module
/// return `Logger(OSLog.disabled)`, which the OS optimises to a no-op.
public final class KlaviyoLogConfig: @unchecked Sendable {
    public static let shared = KlaviyoLogConfig()

    private let lock = NSLock()
    private var _isLoggingEnabled: Bool = true

    private init() {}

    /// Whether logging is currently enabled across all Klaviyo SDK modules.
    public var isLoggingEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isLoggingEnabled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isLoggingEnabled = newValue
        }
    }
}

// MARK: - Logger Convenience Initializers

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = "com.klaviyo.klaviyo-swift-sdk.klaviyoCore"

    init(category: String) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}

// MARK: - Loggers

@available(iOS 14.0, *)
extension Logger {
    /// Logger for ``Codable`` events (JSON encoding & decoding)
    static var codable: Logger {
        KlaviyoLogConfig.shared.isLoggingEnabled ? Logger(category: "Encoding/Decoding Logger") : Logger(OSLog.disabled)
    }

    /// Logger for networking events
    static var networking: Logger {
        KlaviyoLogConfig.shared.isLoggingEnabled ? Logger(category: "Networking") : Logger(OSLog.disabled)
    }

    /// Logger for app navigation and deep linking events
    static var navigation: Logger {
        KlaviyoLogConfig.shared.isLoggingEnabled ? Logger(category: "Linking and Navigation") : Logger(OSLog.disabled)
    }
}
