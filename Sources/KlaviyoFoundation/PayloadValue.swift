//
//  PayloadValue.swift
//  klaviyo-swift-sdk
//

import Foundation

/// Helpers for reading an APNs `userInfo`, whose nested dictionaries bridge as `[String: Any]`,
/// `[AnyHashable: Any]` or `NSDictionary`.
package enum PayloadValue {
    /// A string-keyed dictionary, skipping any non-string keys. `nil` for anything that is not a dictionary.
    package static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        guard let dictionary = value as? [AnyHashable: Any] else { return nil }
        return dictionary.reduce(into: [:]) { result, pair in
            if let key = pair.key as? String { result[key] = pair.value }
        }
    }
}
