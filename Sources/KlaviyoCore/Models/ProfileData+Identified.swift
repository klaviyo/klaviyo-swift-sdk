//
//  ProfileData+Identified.swift
//  klaviyo-swift-sdk
//

extension ProfileData {
    /// `true` when the profile has a non-empty email, phone number, or external ID.
    package var isIdentified: Bool {
        [email, phoneNumber, externalId].contains { $0?.isEmpty == false }
    }
}
