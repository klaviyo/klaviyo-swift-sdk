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
