//
//  PushPayload.swift
//  KlaviyoSwift
//

import Foundation

/// Shared parsing helpers for the raw APNs `userInfo` dictionary, so the "key_value_pairs" key and
/// its expected shape are defined in one place instead of being repeated at every call site.
enum PushPayload {
    static let keyValuePairsKey = "key_value_pairs"

    static func customData(from userInfo: [AnyHashable: Any]) -> [String: String] {
        userInfo[keyValuePairsKey] as? [String: String] ?? [:]
    }

    /// `aps.alert` can be a dictionary (`{ "title": ..., "body": ... }`) or a plain string
    /// (body text only, no title) — normalize both shapes to a single title/body pair.
    static func alertTitleAndBody(from userInfo: [AnyHashable: Any]) -> (title: String, body: String) {
        let alert = (userInfo["aps"] as? [String: Any])?["alert"]
        switch alert {
        case let dict as [String: Any]:
            return (dict["title"] as? String ?? "", dict["body"] as? String ?? "")
        case let text as String:
            return ("", text)
        default:
            return ("", "")
        }
    }

    /// Whether this payload carries a visible alert at all. Pushes without one (truly silent
    /// pushes) never trigger `willPresent`, regardless of app state.
    static func hasVisibleAlert(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["aps"] as? [String: Any])?["alert"] != nil
    }
}
