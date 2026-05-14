//
//  JWTParser.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

import Foundation
import OSLog

/// Pure-Swift parser for the foundational subset of RFC 7519 that the SDK depends on.
///
/// The parser splits a compact JWT into its three segments, Base64URL-decodes the payload,
/// JSON-decodes the `exp` and `iat` (NumericDate) claims, and applies a clock-skew leeway to
/// the expiration check. All other claims are ignored.
///
/// The SDK never verifies the token's cryptographic signature; the Klaviyo backend is the
/// security boundary for that. This type exists purely so the auth-token system can decide
/// whether a returned token is usable and when it should be refreshed.
enum JWTParser {
    /// Clock-skew leeway subtracted from `exp` before comparing to the current time.
    ///
    /// A token is treated as expired when `now >= exp - leeway`. The 15-second window keeps
    /// the SDK from injecting a token that the Klaviyo backend would reject due to clock
    /// drift between the device and the backend.
    static let defaultLeeway: TimeInterval = 15

    // Cyclomatic complexity is intrinsic here: every validation step inlines its own
    // OSLog call behind an iOS 14 availability guard, which doubles the apparent branch
    // count. Routing through a logging wrapper would lose the per-failure call site.
    // swiftlint:disable cyclomatic_complexity

    /// Parses a JWT string and validates the `exp` and `iat` claims.
    ///
    /// - Parameters:
    ///   - token: The raw JWT string.
    ///   - currentTime: The current time used for the expiration check. Injectable to make
    ///     tests deterministic. Defaults to `Date()`.
    ///   - leeway: Clock-skew leeway subtracted from `exp`. Defaults to ``defaultLeeway``.
    /// - Returns: A ``ValidatedToken`` on success, or a ``JWTValidationFailure`` describing
    ///   why the token was rejected.
    static func parseAndValidate(
        _ token: String,
        currentTime: Date = Date(),
        leeway: TimeInterval = JWTParser.defaultLeeway
    ) -> Result<ValidatedToken, JWTValidationFailure> {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            if #available(iOS 14.0, *) {
                Logger.auth.warning("JWT validation failed: malformed structure")
            }
            return .failure(.malformedStructure)
        }

        guard let payloadData = base64URLDecode(String(segments[1])) else {
            if #available(iOS 14.0, *) {
                Logger.auth.warning("JWT validation failed: malformed base64URL payload")
            }
            return .failure(.malformedBase64)
        }

        let claims: JWTClaims
        do {
            claims = try JSONDecoder().decode(JWTClaims.self, from: payloadData)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.auth.warning("JWT validation failed: malformed JSON payload")
            }
            return .failure(.malformedJSON)
        }

        guard let expiresAtSeconds = claims.expiresAtSeconds else {
            if #available(iOS 14.0, *) {
                Logger.auth.warning("JWT validation failed: missing exp claim")
            }
            return .failure(.missingExpClaim)
        }
        guard let issuedAtSeconds = claims.issuedAtSeconds else {
            if #available(iOS 14.0, *) {
                Logger.auth.warning("JWT validation failed: missing iat claim")
            }
            return .failure(.missingIatClaim)
        }

        if currentTime.timeIntervalSince1970 >= expiresAtSeconds - leeway {
            if #available(iOS 14.0, *) {
                Logger.auth.warning("JWT validation failed: expired on receipt")
            }
            return .failure(.expiredOnReceipt)
        }

        return .success(ValidatedToken(
            rawToken: token,
            expiresAt: Date(timeIntervalSince1970: expiresAtSeconds),
            issuedAt: Date(timeIntervalSince1970: issuedAtSeconds)
        ))
    }

    // swiftlint:enable cyclomatic_complexity

    /// Decodes a Base64URL string (RFC 7515 §2): `+` is replaced by `-`, `/` by `_`, and
    /// trailing `=` padding is omitted. We reverse those substitutions and re-pad before
    /// handing off to `Data(base64Encoded:)`.
    private static func base64URLDecode(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingNeeded = (4 - normalized.count % 4) % 4
        normalized.append(String(repeating: "=", count: paddingNeeded))
        return Data(base64Encoded: normalized)
    }
}

/// Subset of the JWT payload claims that the SDK reads. Other claims are intentionally not
/// decoded — `JSONDecoder` ignores unknown keys by default.
private struct JWTClaims: Decodable {
    let expiresAtSeconds: TimeInterval?
    let issuedAtSeconds: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case expiresAtSeconds = "exp"
        case issuedAtSeconds = "iat"
    }
}
