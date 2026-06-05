//
//  KlaviyoIdentity+Forms.swift
//  klaviyo-swift-sdk
//
//  Forms-specific extensions on KlaviyoIdentity: HTML serialization for webview
//  injection and debug formatting. Kept in KlaviyoForms rather than KlaviyoCore
//  because the encoding format and debug layout are IAF implementation details.
//

import Foundation
import KlaviyoCore
import OSLog

extension KlaviyoIdentity: CustomDebugStringConvertible {
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
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = try encoder.encode(self)
        return String(data: jsonData, encoding: .utf8) ?? ""
    }
}
