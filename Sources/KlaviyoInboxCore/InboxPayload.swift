//
//  InboxPayload.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation

/// Helpers for reading an APNs `userInfo`, whose nested values bridge as `[String: Any]`,
/// `[AnyHashable: Any]` or `NSDictionary`, and whose numbers arrive as `NSNumber`.
package enum InboxPayload {
    private static let deviceTokenKey = "pt"
    private static let metadataKey = "_k"
    private static let bodyKey = "body"
    private static let emptyJSONObject = Data("{}".utf8)

    package static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        guard let dictionary = value as? [AnyHashable: Any] else { return nil }
        var result: [String: Any] = [:]
        for (key, element) in dictionary {
            if let key = key as? String { result[key] = element }
        }
        return result
    }

    /// A string, or a number rendered as one. `nil` for null, containers and everything else.
    package static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    /// Like `string`, but nested dictionaries and arrays become compact sorted JSON. `nil` for null.
    package static func stringified(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = string(value) { return string }
        let safe = jsonSafe(value)
        guard JSONSerialization.isValidJSONObject(safe),
              let data = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]) else {
            return "\(value)"
        }
        return String(data: data, encoding: .utf8)
    }

    package static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return intClamped(double) }
        if let number = value as? NSNumber { return intClamped(number.doubleValue) }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            return Int(trimmed)
        }
        return nil
    }

    package static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        guard let int = value as? Int ?? (value as? NSNumber)?.intValue else { return nil }
        return int != 0
    }

    /// ISO 8601 (with or without fractional seconds), or epoch seconds or milliseconds.
    package static func date(_ value: Any?) -> Date? {
        if let string = value as? String {
            if let date = isoDate(string, fractional: true) ?? isoDate(string, fractional: false) {
                return date
            }
            return Double(string).map(epoch)
        }
        if let number = value as? NSNumber { return epoch(number.doubleValue) }
        return nil
    }

    /// JSON of the whole payload with the device token in `body._k` removed.
    package static func snapshot(_ userInfo: [AnyHashable: Any]) -> Data {
        var payload = jsonSafe(userInfo) as? [String: Any] ?? [:]
        if var body = payload[bodyKey] as? [String: Any],
           var metadata = body[metadataKey] as? [String: Any] {
            metadata.removeValue(forKey: deviceTokenKey)
            body[metadataKey] = metadata
            payload[bodyKey] = body
        }
        return serialize(payload)
    }

    /// JSON of a properties dictionary (`_k`) with the top-level device token removed.
    package static func snapshot(_ properties: [String: Any]) -> Data {
        var safe = jsonSafe(properties) as? [String: Any] ?? [:]
        safe.removeValue(forKey: deviceTokenKey)
        return serialize(safe)
    }

    // MARK: - Private

    private static func isoDate(_ string: String, fractional: Bool) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func epoch(_ number: Double) -> Date {
        // Anything past year ~5138 in seconds is milliseconds.
        Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number)
    }

    /// Truncates toward zero like `Int(_:)`, but returns `nil` instead of trapping when the value
    /// is non-finite or outside `Int.min...Int.max`. The capture path must never crash the NSE.
    private static func intClamped(_ double: Double) -> Int? {
        guard double.isFinite else { return nil }
        return Int(exactly: double.rounded(.towardZero))
    }

    /// Recursively converts a value into something `JSONSerialization` accepts: string keys only,
    /// non-finite numbers, `Date` and `Data` stringified, and anything unknown described.
    private static func jsonSafe(_ value: Any) -> Any {
        switch value {
        case let dictionary as [AnyHashable: Any]:
            var result: [String: Any] = [:]
            for (key, element) in dictionary {
                if let key = key as? String { result[key] = jsonSafe(element) }
            }
            return result
        case let array as [Any]:
            return array.map(jsonSafe)
        case let string as String:
            return string
        case let number as NSNumber:
            return number.doubleValue.isFinite ? number : "\(number)"
        case is NSNull:
            return NSNull()
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let data as Data:
            return data.base64EncodedString()
        default:
            return "\(value)"
        }
    }

    /// `JSONSerialization.data` raises an Objective-C exception on invalid input, which Swift cannot
    /// catch, so validity is checked first.
    private static func serialize(_ object: Any) -> Data {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return emptyJSONObject
        }
        return data
    }
}
