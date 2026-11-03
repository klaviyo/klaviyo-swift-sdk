//
//  String+RedactingToken.swift
//  klaviyo-swift-sdk
//

import Foundation

extension String {
    private static let jsonTokenPattern = try? NSRegularExpression(pattern: "\"token\"\\s*:\\s*\"[^\"]*\"")

    /// This string with the value of every JSON `"token"` field replaced by `<redacted>`.
    var redactingJSONToken: String {
        guard let regex = Self.jsonTokenPattern else { return self }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(
            in: self,
            range: range,
            withTemplate: "\"token\":\"<redacted>\""
        )
    }
}
