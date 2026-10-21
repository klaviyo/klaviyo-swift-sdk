//
//  String+JavaScript.swift
//  klaviyo-swift-sdk
//

import Foundation

extension String {
    /// This string as a quoted JavaScript string literal, safe to embed in a script whatever
    /// characters it contains.
    var javaScriptStringLiteral: String {
        guard let data = try? JSONEncoder().encode(self),
              let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
        return literal
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
