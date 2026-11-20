//
//  IdentityTransitionParityTests.swift
//  KlaviyoCore
//
//  Proves the expanded IdentityTransition decides the auth-token chain exactly as the
//  previous three-case classifier did.
//

@testable import KlaviyoCore

#if canImport(Testing)
import Testing

struct IdentityTransitionParityTests {
    private enum LegacyTransition: Equatable {
        case unchanged, compatible, replacement
    }

    /// A faithful copy of the classifier this type replaced, used as the parity oracle.
    private static func legacyClassify(previous: ProfileData?, next: ProfileData) -> LegacyTransition {
        func nonEmpty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        func normalized(_ identifiers: ProfileData) -> ProfileData {
            ProfileData(
                email: nonEmpty(identifiers.email),
                phoneNumber: nonEmpty(identifiers.phoneNumber),
                externalId: nonEmpty(identifiers.externalId),
                anonymousId: nonEmpty(identifiers.anonymousId)
            )
        }
        func sharesStableIdentifierWithoutConflict(_ previous: ProfileData, _ next: ProfileData) -> Bool {
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

        let next = normalized(next)
        guard let previous = previous.map(normalized) else { return .compatible }
        if previous == next { return .unchanged }
        return sharesStableIdentifierWithoutConflict(previous, next) ? .compatible : .replacement
    }

    private static let profiles: [ProfileData] = {
        let emails: [String?] = [nil, "", "a@x.com", "b@x.com"]
        let phones: [String?] = [nil, "", "+15555550100"]
        let externalIds: [String?] = [nil, "", "external-x"]
        let anonymousIds: [String?] = [nil, "", "anon-1", "anon-2"]
        return emails.flatMap { email in
            phones.flatMap { phone in
                externalIds.flatMap { externalId in
                    anonymousIds.map {
                        ProfileData(email: email, phoneNumber: phone, externalId: externalId, anonymousId: $0)
                    }
                }
            }
        }
    }()

    @Test
    func discardsAuthTokenAndUnchangedMatchTheLegacyClassifier() {
        let previousProfiles: [ProfileData?] = [nil] + Self.profiles
        var checked = 0
        for previous in previousProfiles {
            for next in Self.profiles {
                let transition = IdentityTransition.classify(previous: previous, next: next)
                let legacy = Self.legacyClassify(previous: previous, next: next)
                let pair = "\(String(describing: previous)) -> \(next) (new \(transition), legacy \(legacy))"
                #expect(transition.discardsAuthToken == (legacy == .replacement), "discardsAuthToken: \(pair)")
                #expect((transition == .unchanged) == (legacy == .unchanged), "unchanged: \(pair)")
                checked += 1
            }
        }
        #expect(checked == previousProfiles.count * Self.profiles.count)
    }
}
#endif
