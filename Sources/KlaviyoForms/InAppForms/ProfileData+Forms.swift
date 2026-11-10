//
//  ProfileData+Forms.swift
//  klaviyo-swift-sdk
//

import Foundation
import KlaviyoCore
import OSLog

extension ProfileData: CustomDebugStringConvertible {
    // Hidden from the generated docs: this conformance is a logging aid, not API for integrators.
    // Keep the attribute on the member. On the extension, SwiftFormat 0.51.2's
    // `extensionAccessControl` rule mangles it into code that doesn't compile.
    @_documentation(visibility: internal)
    public var debugDescription: String {
        """
        email: \t\t\t\(email ?? "<no email>")
        phoneNumber: \t\(phoneNumber ?? "<no phoneNumber>")
        anonymousId: \t\(anonymousId ?? "<no anonymousId>")
        externalId: \t\(externalId ?? "<no externalId>")
        """
    }

    /// Encodes the identity as a JSON string suitable for injection into the forms webview
    /// via `document.head.setAttribute('data-klaviyo-profile', ...)`.
    func toHtmlString() throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let jsonData = try encoder.encode(self)
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error encoding profile data: \(error)")
            }
            return ""
        }
    }
}
