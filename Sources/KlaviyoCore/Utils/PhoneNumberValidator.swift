//
//  PhoneNumberValidator.swift
//  KlaviyoCore
//
//  Klaviyo silently drops phone numbers that lack a country code while still returning a
//  success status, so the SDK rejects them client-side instead.
//
//  This is a coarse check, not full validation: the server also drops numbers that are not
//  valid for their country code (e.g. `+1234567`), which would need per-country rules.
//

import Foundation

public enum PhoneNumberValidator {
    /// E.164 allows at most 15 digits including the country code.
    static let maxDigits = 15
    /// Shortest plausible international number (country code + subscriber digits).
    static let minDigits = 7
    static let countryCodePrefix: Character = "+"
    /// Formatting characters people commonly type and that carry no meaning.
    private static let separators = CharacterSet(charactersIn: " -().\u{00A0}")

    /// Returns `true` when `phoneNumber` has a leading `+` followed by 7-15 ASCII digits.
    /// Spaces, dashes, dots and parentheses are ignored. Letters are rejected: the server converts
    /// them to keypad digits (e.g. `abc` becomes `222`), which is not intended behavior.
    public static func isValid(_ phoneNumber: String) -> Bool {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == countryCodePrefix else { return false }

        let remainder = trimmed.dropFirst().unicodeScalars.filter { !separators.contains($0) }
        guard (minDigits...maxDigits).contains(remainder.count) else { return false }
        return remainder.allSatisfy { ("0"..."9").contains($0) }
    }

    /// Developer-facing message for a rejected number. Deliberately omits the number itself (PII).
    public static let invalidFormatWarning = """
    phone number is not in a valid format and will be ignored. Phone numbers must start with + and \
    a country code, e.g. +12345678901 (E.164).
    """
}
