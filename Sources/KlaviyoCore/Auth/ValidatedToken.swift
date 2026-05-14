//
//  ValidatedToken.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

import Foundation

/// A JWT that has passed SDK-side parsing and validation.
///
/// The SDK reads only the `exp` and `iat` claims; all other claims (`sub`, audience, issuer,
/// custom claims) remain opaque and are resolved by the Klaviyo backend. The SDK does not
/// verify the token's signature — the backend is the security boundary.
struct ValidatedToken: Equatable, Hashable {
    /// The raw JWT string as supplied to the SDK.
    let rawToken: String

    /// The `exp` (expiration time) claim decoded from a NumericDate to a `Date`.
    let expiresAt: Date

    /// The `iat` (issued at) claim decoded from a NumericDate to a `Date`.
    let issuedAt: Date
}
