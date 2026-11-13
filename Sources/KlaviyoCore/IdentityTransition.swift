//
//  IdentityTransition.swift
//  KlaviyoCore
//

/// How a profile's identifiers changed, as decided by ``classify(previous:next:)``.
///
/// The result only describes the change; it never decides what to do about it. Each consumer
/// maps the cases to its own action with an exhaustive `switch` that has no `default`, so adding a
/// case fails to compile until every consumer has decided. The auth-token chain's mapping lives in
/// `Auth/IdentityTransition+AuthToken.swift`.
///
/// "ids" below means email, phone number and external ID. An id is *shared* when it is present on
/// both sides and equal, and *conflicting* when it is present on both sides and different.
package enum IdentityTransition: Equatable {
    /// There was no previous profile.
    case initial
    /// Every identifier, anonymous ID included, is the same.
    case unchanged
    /// The previous profile had no ids and the next one has at least one.
    case anonymousToIdentified
    /// The previous profile had at least one id and the next one has none.
    case cleared
    /// At least one id is shared and at least one conflicts (for example A+X becoming B+X).
    case partialConflict
    /// The ids are equal and at least one is present, but the anonymous ID differs.
    case anonymousIdRotated
    /// At least one id is shared, none conflicts, the next profile gained ids and lost none.
    case additive
    /// At least one id is shared, none conflicts, the next profile lost ids and gained none.
    case subtractive
    /// At least one id is shared, none conflicts, the next profile both gained and lost ids.
    case reshaped
    /// Everything else: both sides have ids but share none, or neither has ids and the anonymous
    /// ID differs.
    case replacement

    /// Classifies the change from `previous` to `next`.
    ///
    /// Empty strings are treated as absent; values are otherwise compared exactly, with no
    /// trimming or case folding. The anonymous ID takes part only in `unchanged`,
    /// `anonymousIdRotated` and the no-ids `replacement`; it is ignored when deciding whether ids
    /// are shared or conflict. The cases are evaluated top to bottom, the first match wins, and
    /// together they cover every input:
    /// 1. `initial`: `previous` is `nil`.
    /// 2. `unchanged`: all four identifiers are equal.
    /// 3. `anonymousToIdentified`: `previous` has no ids, `next` has some.
    /// 4. `cleared`: `previous` has ids, `next` has none.
    /// 5. `partialConflict`: at least one shared id and at least one conflict.
    /// 6. `anonymousIdRotated`: at least one shared id, nothing conflicting, gained or lost
    ///    (so the ids are equal), and, as it is not `unchanged`, a different anonymous ID.
    /// 7. `additive`: shared, no conflict, ids gained, none lost.
    /// 8. `subtractive`: shared, no conflict, ids lost, none gained.
    /// 9. `reshaped`: shared, no conflict, ids both gained and lost.
    /// 10. `replacement`: anything else.
    package static func classify(previous: ProfileData?, next: ProfileData) -> IdentityTransition {
        guard let previous = previous.map(normalized) else { return .initial }
        let next = normalized(next)
        if previous == next { return .unchanged }

        return classifyChange(idCounts(previous, next))
    }

    /// Cases 3 to 10, for two normalized profiles that are not `unchanged`.
    private static func classifyChange(_ counts: IdCounts) -> IdentityTransition {
        let previousHasIds = counts.shared + counts.conflicting + counts.lost > 0
        let nextHasIds = counts.shared + counts.conflicting + counts.gained > 0
        switch (previousHasIds, nextHasIds) {
        case (false, true): return .anonymousToIdentified
        case (true, false): return .cleared
        case (false, false): return .replacement
        case (true, true): break
        }

        if counts.shared > 0, counts.conflicting > 0 { return .partialConflict }
        guard counts.shared > 0 else { return .replacement }
        switch (counts.gained > 0, counts.lost > 0) {
        case (false, false): return .anonymousIdRotated
        case (true, false): return .additive
        case (false, true): return .subtractive
        case (true, true): return .reshaped
        }
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

    /// How many of the three ids are shared, conflicting, gained (only on `next`) or lost (only on
    /// `previous`). Both profiles must already be normalized.
    private struct IdCounts {
        var shared = 0
        var conflicting = 0
        var gained = 0
        var lost = 0
    }

    private static func idCounts(_ previous: ProfileData, _ next: ProfileData) -> IdCounts {
        let ids: [KeyPath<ProfileData, String?>] = [\.email, \.phoneNumber, \.externalId]
        var counts = IdCounts()
        for keyPath in ids {
            switch (previous[keyPath: keyPath], next[keyPath: keyPath]) {
            case let (previousValue?, nextValue?):
                if previousValue == nextValue { counts.shared += 1 } else { counts.conflicting += 1 }
            case (nil, _?): counts.gained += 1
            case (_?, nil): counts.lost += 1
            case (nil, nil): break
            }
        }
        return counts
    }
}
