//
//  IdentityTransition.swift
//  KlaviyoCore
//

/// How a profile's identifiers changed, as decided by ``classify(previous:next:)``.
///
/// Matches the classification onsite applies to identifier changes: an auth token survives
/// `unchanged` and `compatible` transitions and is discarded on a `replacement`.
package enum IdentityTransition: Equatable {
    /// Every identifier, anonymous ID included, is the same.
    case unchanged
    /// The identifiers changed but describe the same profile, or there was no previous
    /// profile.
    case compatible
    /// The identifiers describe a different profile than before.
    case replacement

    /// Classifies the change from `previous` to `next`.
    ///
    /// Empty strings are treated as absent; values are otherwise compared exactly, with no
    /// trimming or case folding.
    /// - `unchanged`: all four identifiers are equal.
    /// - `compatible`: `previous` is `nil`, or email, phone number and external ID share at
    ///   least one equal value and none is present on both sides with different values.
    ///   Identifiers present on only one side, and the anonymous ID, are ignored.
    /// - `replacement`: any other change.
    package static func classify(previous: ProfileData?, next: ProfileData) -> IdentityTransition {
        let next = normalized(next)
        guard let previous = previous.map(normalized) else { return .compatible }
        if previous == next { return .unchanged }
        return sharesStableIdentifierWithoutConflict(previous, next) ? .compatible : .replacement
    }

    private static func normalized(_ identifiers: ProfileData) -> ProfileData {
        ProfileData(
            email: nonEmpty(identifiers.email),
            phoneNumber: nonEmpty(identifiers.phoneNumber),
            externalId: nonEmpty(identifiers.externalId),
            anonymousId: nonEmpty(identifiers.anonymousId)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func sharesStableIdentifierWithoutConflict(
        _ previous: ProfileData,
        _ next: ProfileData
    ) -> Bool {
        let stableIdentifiers: [KeyPath<ProfileData, String?>] = [\.email, \.phoneNumber, \.externalId]
        var sharesIdentifier = false
        for keyPath in stableIdentifiers {
            guard let previousValue = previous[keyPath: keyPath],
                  let nextValue = next[keyPath: keyPath] else { continue }
            if previousValue != nextValue { return false }
            sharesIdentifier = true
        }
        return sharesIdentifier
    }
}
