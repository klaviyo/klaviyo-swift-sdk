//
//  FormsPreview.swift
//  klaviyo-swift-sdk
//

import Foundation

/// Shared rules for the in-app forms draft-preview token: the key name and query parameter parsing.
package enum FormsPreview {
    /// Key carrying a preview token: a deep link query parameter, and a push key/value pair.
    package static let previewTokenKey = "klaviyo-forms-preview"

    /// The raw ``previewTokenKey`` query parameter value of `url`, or `nil` when the URL has no
    /// such parameter. Works for custom schemes and http(s) links, with any host and path.
    /// The value is not validated; see ``FormsPreviewTokenStore/validate(_:)``.
    package static func previewTokenParameter(in url: URL) -> String? {
        previewTokenParameter(inURLString: url.absoluteString)
    }

    /// `url` with every ``previewTokenKey`` query parameter removed, keeping all other parts.
    /// Returns `url` unchanged when it has no such parameter.
    package static func removingPreviewTokenParameter(from url: URL) -> URL {
        let stripped = removingPreviewTokenParameter(fromURLString: url.absoluteString)
        guard stripped != url.absoluteString else { return url }
        return URL(string: stripped) ?? url
    }

    /// The percent-decoded ``previewTokenKey`` query parameter value of `urlString`, or `nil`
    /// when it has no such parameter. Reads the text as written, so it also works when
    /// `URL(string:)` would reject it. The query is the part after the first `?` and before
    /// any `#`; the first matching parameter wins. The value is not validated; see
    /// ``FormsPreviewTokenStore/validate(_:)``.
    package static func previewTokenParameter(inURLString urlString: String) -> String? {
        guard let query = splitQuery(of: urlString).query,
              let parameter = query.split(separator: "&", omittingEmptySubsequences: false)
              .first(where: { parameterName($0) == previewTokenKey })
        else { return nil }
        let value = parameter.drop { $0 != "=" }.dropFirst()
        return String(value).removingPercentEncoding ?? String(value)
    }

    /// `urlString` with every ``previewTokenKey`` query parameter removed. Every other byte is
    /// kept as written, including the encoding of the remaining parameters, and the `?` is
    /// dropped when no parameters remain. Works whether or not `URL(string:)` accepts the text.
    /// Returns `urlString` unchanged when it has no such parameter.
    package static func removingPreviewTokenParameter(fromURLString urlString: String) -> String {
        let parts = splitQuery(of: urlString)
        guard let query = parts.query else { return urlString }
        let segments = query.split(separator: "&", omittingEmptySubsequences: false)
        let kept = segments.filter { parameterName($0) != previewTokenKey }
        guard kept.count != segments.count else { return urlString }
        let remaining = kept.joined(separator: "&")
        return parts.base + (remaining.isEmpty ? "" : "?" + remaining) + parts.fragment
    }

    private static func parameterName(_ parameter: Substring) -> Substring {
        parameter.prefix { $0 != "=" }
    }

    private static func splitQuery(of urlString: String) -> (base: String, query: String?, fragment: String) {
        let fragmentStart = urlString.firstIndex(of: "#") ?? urlString.endIndex
        let beforeFragment = urlString[..<fragmentStart]
        let fragment = String(urlString[fragmentStart...])
        guard let queryStart = beforeFragment.firstIndex(of: "?") else {
            return (String(beforeFragment), nil, fragment)
        }
        return (
            String(beforeFragment[..<queryStart]),
            String(beforeFragment[beforeFragment.index(after: queryStart)...]),
            fragment
        )
    }
}
