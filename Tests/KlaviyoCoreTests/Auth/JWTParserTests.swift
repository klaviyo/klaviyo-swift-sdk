//
//  JWTParserTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2026-05-14.
//

@testable import KlaviyoCore
import Foundation

#if canImport(Testing)
import Testing

struct JWTParserTests {
    static let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)
    static let defaultIat: TimeInterval = 1_700_000_000 - 60
    static let defaultExp: TimeInterval = 1_700_000_000 + 3600

    // MARK: - Happy path

    @Test
    func validTokenReturnsValidatedTokenWithDecodedClaims() throws {
        let token = try makeJWT()

        let validated = try requireValidated(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow)
        )

        #expect(validated.rawToken == token)
        #expect(validated.issuedAt == Date(timeIntervalSince1970: Self.defaultIat))
        #expect(validated.expiresAt == Date(timeIntervalSince1970: Self.defaultExp))
    }

    @Test
    func validTokenIgnoresUnknownClaims() throws {
        let token = try makeJWT(extraClaims: [
            "sub": "user-123",
            "aud": "klaviyo",
            "iss": "https://auth.example.com",
            "custom_field": ["nested": 42]
        ])

        let validated = try requireValidated(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow)
        )

        #expect(validated.issuedAt == Date(timeIntervalSince1970: Self.defaultIat))
        #expect(validated.expiresAt == Date(timeIntervalSince1970: Self.defaultExp))
    }

    @Test
    func validTokenDecodesFractionalNumericDates() throws {
        let issuedAtSeconds = 1_700_000_000.25
        let expiresAtSeconds = 1_700_003_600.75
        let token = try makeJWT(issuedAt: issuedAtSeconds, expiresAt: expiresAtSeconds)

        let validated = try requireValidated(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow)
        )

        #expect(validated.issuedAt == Date(timeIntervalSince1970: issuedAtSeconds))
        #expect(validated.expiresAt == Date(timeIntervalSince1970: expiresAtSeconds))
    }

    // MARK: - Malformed structure

    @Test(arguments: ["", "only-one-segment", "header.payload", "a.b.c.d"])
    func malformedStructureIsRejected(token: String) {
        expectFailure(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow),
            .malformedStructure
        )
    }

    // MARK: - Malformed Base64URL

    @Test
    func malformedBase64PayloadIsRejected() throws {
        let header = try base64URLEncode(JSONSerialization.data(withJSONObject: ["alg": "HS256"]))
        // `*` is not a valid base64URL character.
        let token = "\(header).****.signature"

        expectFailure(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow),
            .malformedBase64
        )
    }

    // MARK: - Malformed JSON

    @Test
    func nonJSONPayloadIsRejected() throws {
        let header = try base64URLEncode(JSONSerialization.data(withJSONObject: ["alg": "HS256"]))
        let payload = base64URLEncodeString("not-actually-json")
        let token = "\(header).\(payload).signature"

        expectFailure(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow),
            .malformedJSON
        )
    }

    @Test
    func jsonArrayPayloadIsRejected() throws {
        let header = try base64URLEncode(JSONSerialization.data(withJSONObject: ["alg": "HS256"]))
        let payload = try base64URLEncode(JSONSerialization.data(withJSONObject: [1, 2, 3]))
        let token = "\(header).\(payload).signature"

        expectFailure(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow),
            .malformedJSON
        )
    }

    @Test
    func expAsStringIsRejected() throws {
        let token = try makeJWT(payload: [
            "iat": Self.defaultIat,
            "exp": "not-a-number"
        ])

        expectFailure(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow),
            .malformedJSON
        )
    }

    // MARK: - Missing claims

    @Test
    func missingExpClaimIsRejected() throws {
        let token = try makeJWT(payload: ["iat": Self.defaultIat])

        expectFailure(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow),
            .missingExpClaim
        )
    }

    @Test
    func missingIatClaimIsRejected() throws {
        let token = try makeJWT(payload: ["exp": Self.defaultExp])

        expectFailure(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow),
            .missingIatClaim
        )
    }

    @Test
    func emptyPayloadIsRejectedAsMissingExp() throws {
        let token = try makeJWT(payload: [:])

        expectFailure(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow),
            .missingExpClaim
        )
    }

    // MARK: - Expiration

    @Test
    func nowEqualToExpIsRejected() throws {
        let token = try makeJWT()

        expectFailure(
            JWTParser.parseAndValidate(
                token,
                currentTime: Date(timeIntervalSince1970: Self.defaultExp)
            ),
            .expiredOnReceipt
        )
    }

    @Test
    func nowPastExpIsRejected() throws {
        let token = try makeJWT()

        expectFailure(
            JWTParser.parseAndValidate(
                token,
                currentTime: Date(timeIntervalSince1970: Self.defaultExp + 1)
            ),
            .expiredOnReceipt
        )
    }

    @Test
    func nowAtLeewayBoundaryIsRejected() throws {
        // `now == exp - leeway` is treated as expired (>= rule).
        let token = try makeJWT()
        let leeway: TimeInterval = 15
        let currentTime = Date(timeIntervalSince1970: Self.defaultExp - leeway)

        expectFailure(
            JWTParser.parseAndValidate(token, currentTime: currentTime, leeway: leeway),
            .expiredOnReceipt
        )
    }

    @Test
    func nowJustInsideLeewayIsAccepted() throws {
        // `now == exp - leeway - epsilon` is still valid.
        let token = try makeJWT()
        let leeway: TimeInterval = 15
        let currentTime = Date(timeIntervalSince1970: Self.defaultExp - leeway - 0.001)

        let validated = try requireValidated(
            JWTParser.parseAndValidate(token, currentTime: currentTime, leeway: leeway)
        )
        #expect(validated.rawToken == token)
    }

    @Test
    func zeroLeewayMovesExpiryBoundaryToExp() throws {
        let token = try makeJWT()

        // With leeway = 0, `now == exp - 1` is still valid.
        let justBefore = Date(timeIntervalSince1970: Self.defaultExp - 1)
        _ = try requireValidated(
            JWTParser.parseAndValidate(token, currentTime: justBefore, leeway: 0)
        )

        // ...but `now == exp` is expired.
        expectFailure(
            JWTParser.parseAndValidate(
                token,
                currentTime: Date(timeIntervalSince1970: Self.defaultExp),
                leeway: 0
            ),
            .expiredOnReceipt
        )
    }

    @Test
    func defaultLeewayIs15Seconds() {
        #expect(JWTParser.defaultLeeway == 15)
    }

    // MARK: - Base64URL handling

    @Test
    func payloadWithUrlSafeCharactersDecodesCorrectly() throws {
        // Force the payload's base64 encoding to use `-` and `_` substitutions by
        // choosing claim values that produce those bytes when JSON-encoded.
        //
        // Standard base64 emits `+` and `/` for byte sequences containing these bits;
        // the parser must accept the URL-safe substitutions.
        let token = try makeJWT(extraClaims: ["data": ">>>>???"])

        let validated = try requireValidated(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow)
        )
        #expect(validated.expiresAt == Date(timeIntervalSince1970: Self.defaultExp))
    }

    @Test
    func payloadWithoutPaddingDecodesCorrectly() throws {
        // makeJWT() always strips `=` padding (RFC 7515 §2). This test exists to make
        // the no-padding case an explicit assertion on the parser's input contract.
        let token = try makeJWT()
        #expect(!token.contains("="), "JWT segments should not contain `=` padding")

        _ = try requireValidated(
            JWTParser.parseAndValidate(token, currentTime: Self.referenceNow)
        )
    }

    // MARK: - Result helpers

    private func requireValidated(
        _ result: Result<ValidatedToken, JWTValidationFailure>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> ValidatedToken {
        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            Issue.record(
                "Expected validated token, got failure: \(error)",
                sourceLocation: sourceLocation
            )
            throw error
        }
    }

    private func expectFailure(
        _ result: Result<ValidatedToken, JWTValidationFailure>,
        _ expected: JWTValidationFailure,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        switch result {
        case let .success(value):
            Issue.record(
                "Expected failure \(expected), got success: \(value)",
                sourceLocation: sourceLocation
            )
        case let .failure(actual):
            #expect(actual == expected, sourceLocation: sourceLocation)
        }
    }
}

// MARK: - JWT Fixture Helpers

extension JWTParserTests {
    /// Builds a JWT with default `iat`/`exp` and optional extra claims.
    fileprivate func makeJWT(
        issuedAt: TimeInterval? = JWTParserTests.defaultIat,
        expiresAt: TimeInterval? = JWTParserTests.defaultExp,
        extraClaims: [String: Any] = [:]
    ) throws -> String {
        var payload: [String: Any] = extraClaims
        if let issuedAt = issuedAt { payload["iat"] = issuedAt }
        if let expiresAt = expiresAt { payload["exp"] = expiresAt }
        return try makeJWT(payload: payload)
    }

    /// Builds a JWT with a caller-specified payload. The header is fixed and the
    /// signature segment is a placeholder — neither is validated by the parser.
    fileprivate func makeJWT(payload: [String: Any]) throws -> String {
        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        let headerSeg = try base64URLEncode(JSONSerialization.data(withJSONObject: header))
        let payloadSeg = try base64URLEncode(JSONSerialization.data(withJSONObject: payload))
        return "\(headerSeg).\(payloadSeg).signature"
    }

    fileprivate func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    fileprivate func base64URLEncodeString(_ string: String) -> String {
        base64URLEncode(Data(string.utf8))
    }
}
#endif
