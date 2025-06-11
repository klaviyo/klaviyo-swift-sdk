//
//  ProfileData.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/21/25.
//

import Foundation
import OSLog

package struct ProfileData: Equatable, CustomDebugStringConvertible {
    package var email: String?
    package var anonymousId: String?
    package var phoneNumber: String?
    package var externalId: String?

    package var debugDescription: String {
        """
        email: \t\t\t\(email ?? "<no email>")
        phoneNumber: \t\(phoneNumber ?? "<no phoneNumber>")
        anonymousId: \t\(anonymousId ?? "<no anonymousId>")
        externalId: \t\(externalId ?? "<no externalId>")
        """
    }
}

extension ProfileData: Encodable {
    package func toHtmlString() throws -> String {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(self)
            let jsonString = String(data: jsonData, encoding: .utf8)
            return jsonString ?? ""
        } catch {
            if #available(iOS 14.0, *) {
                Logger.codableLogger.warning("Error encoding profile data: \(error)")
            }
            return ""
        }
    }
}
