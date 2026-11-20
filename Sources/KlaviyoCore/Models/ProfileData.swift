//
//  ProfileData.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/21/25.
//

public struct ProfileData: Equatable, Codable {
    public var email: String?
    public var phoneNumber: String?
    public var externalId: String?
    public var anonymousId: String?

    public init(
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        anonymousId: String? = nil
    ) {
        self.email = email
        self.phoneNumber = phoneNumber
        self.externalId = externalId
        self.anonymousId = anonymousId
    }
}

extension ProfileData {
    /// A copy with `email`, `phoneNumber` and `externalId` set to `nil` when they are exactly `""`.
    ///
    /// A persisted profile can in principle hold `""` (the legacy migration writes the decoded legacy
    /// profile verbatim), but an empty identifier means the same thing as an absent one. Normalizing
    /// at the store boundary keeps stored identity in a single representation. Only exact emptiness
    /// is normalized — whitespace is not trimmed, so `"  "` is left alone. `anonymousId` is never
    /// normalized: it is identity, not an identifier.
    package var emptyIdentifiersAsNil: ProfileData {
        var normalized = self
        if normalized.email?.isEmpty == true { normalized.email = nil }
        if normalized.phoneNumber?.isEmpty == true { normalized.phoneNumber = nil }
        if normalized.externalId?.isEmpty == true { normalized.externalId = nil }
        return normalized
    }
}
