import Foundation

/// The profile identity state shared across Klaviyo SDK modules.
///
/// Moved to `KlaviyoCore` as a `public` type so that `KlaviyoForms`, `KlaviyoLocation`,
/// and other modules can observe profile data without importing `KlaviyoSwift`.
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
