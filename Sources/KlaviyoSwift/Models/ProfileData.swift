//
//  ProfileData.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/21/25.
//

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
