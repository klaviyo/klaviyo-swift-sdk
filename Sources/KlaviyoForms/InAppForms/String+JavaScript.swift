//
//  String+JavaScript.swift
//  klaviyo-swift-sdk
//

import Foundation

extension String {
    /// This string as a quoted JavaScript string literal, safe to embed in a script whatever
    /// characters it contains.
    var javaScriptStringLiteral: String {
        let encoder = JSONEncoder()
        // `</` is escaped below; keep other slashes readable (e.g. in URLs).
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(self),
              let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
        // JSON leaves these alone, but they matter in JS: `</` can close an enclosing
        // `<script>` element, and U+2028/U+2029 end lines in older JS engines.
        return literal
            .replacingOccurrences(of: "</", with: "<\\/")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// A JS statement that sets the `name` attribute of `document.head` to `value`, with both
    /// encoded as string literals.
    static func setHeadAttributeScript(_ name: String, _ value: String) -> String {
        "document.head.setAttribute(\(name.javaScriptStringLiteral), \(value.javaScriptStringLiteral));"
    }
}
