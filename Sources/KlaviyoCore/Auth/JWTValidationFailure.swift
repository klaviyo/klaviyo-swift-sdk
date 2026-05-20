//
//  JWTValidationFailure.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

import Foundation

/// Reasons a JWT can fail SDK-side validation.
///
/// The SDK does **not** verify the token's cryptographic signature; the Klaviyo backend is the
/// security boundary for that. These cases capture only what the SDK can detect locally:
/// structural problems, missing required claims, or tokens that are already expired at the time
/// of acquisition (applying a clock-skew leeway).
enum JWTValidationFailure: Error, Equatable {
    /// The token did not contain three `.`-separated segments.
    case malformedStructure

    /// The payload segment could not be Base64URL-decoded.
    case malformedBase64

    /// The payload segment did not decode to a JSON object with the expected claim types.
    /// Covers both "not a JSON object" (e.g. payload is a JSON array or non-JSON bytes)
    /// and "claim has the wrong type" (e.g. `exp` is a string instead of a NumericDate).
    case malformedJSON

    /// The `exp` claim was absent from the payload.
    case missingExpClaim

    /// The `iat` claim was absent from the payload.
    case missingIatClaim

    /// The token was already expired at acquisition, after applying clock-skew leeway.
    case expiredOnReceipt
}
