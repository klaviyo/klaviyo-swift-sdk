//
//  FormsPreview.swift
//  klaviyo-swift-sdk
//

import Foundation

/// Shared rules for the in-app forms draft-preview token, used by KlaviyoForms (deep links) and
/// KlaviyoSwift (push opens) so the key name and token format live in one place.
package enum FormsPreview {
    /// Key carrying a preview token: a deep link query parameter, and a push key/value pair.
    /// Move to KlaviyoFoundation once that module exists, since KlaviyoInboxCore needs it too.
    package static let previewTokenKey = "klaviyo-forms-preview"

    /// The raw ``previewTokenKey`` query parameter value of `url`, or `nil` when the URL has no
    /// such parameter. Works for custom schemes and http(s) links, with any host and path.
    /// The value is not validated; see ``FormsPreviewTokenStore/validate(_:)``.
    package static func previewTokenParameter(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == previewTokenKey }
            .map { $0.value ?? "" }
    }

    /// `url` with every ``previewTokenKey`` query parameter removed, keeping all other parts.
    /// Returns `url` unchanged when it has no such parameter.
    package static func removingPreviewTokenParameter(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              items.contains(where: { $0.name == previewTokenKey })
        else { return url }
        let kept = items.filter { $0.name != previewTokenKey }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }
}
