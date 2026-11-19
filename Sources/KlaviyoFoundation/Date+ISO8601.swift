//
//  Date+ISO8601.swift
//  klaviyo-swift-sdk
//

import Foundation

private enum ISO8601Formatters {
    // `ISO8601DateFormatter` is thread-safe, and building one is expensive, so they are shared.
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

package extension Date {
    /// Parses an ISO 8601 internet date-time, with or without fractional seconds.
    /// `nil` if the string is not one.
    init?(iso8601 string: String) {
        guard let date = ISO8601Formatters.fractional.date(from: string)
            ?? ISO8601Formatters.plain.date(from: string) else { return nil }
        self = date
    }

    /// This date as an ISO 8601 internet date-time in UTC, with fractional seconds when present.
    var iso8601String: String {
        let hasFraction = timeIntervalSince1970.truncatingRemainder(dividingBy: 1) != 0
        return (hasFraction ? ISO8601Formatters.fractional : ISO8601Formatters.plain).string(from: self)
    }
}
