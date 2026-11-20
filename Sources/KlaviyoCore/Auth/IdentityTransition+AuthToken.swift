//
//  IdentityTransition+AuthToken.swift
//  KlaviyoCore
//

extension IdentityTransition {
    /// Whether onsite discards its auth token on this transition.
    ///
    /// This is the auth-token chain's mapping only (Auth and Forms). Another consumer, such as a
    /// future inbox, must write its own exhaustive `switch` rather than reuse this one.
    package var discardsAuthToken: Bool {
        switch self {
        case .anonymousToIdentified, .cleared, .partialConflict, .replacement:
            true
        case .initial, .unchanged, .anonymousIdRotated, .additive, .subtractive, .reshaped:
            false
        }
    }
}
