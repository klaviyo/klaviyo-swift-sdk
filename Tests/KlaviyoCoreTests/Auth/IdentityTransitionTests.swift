//
//  IdentityTransitionTests.swift
//  KlaviyoCore
//
//  Mirrors the identifier-transition cases onsite applies to its own auth token.
//

@testable import KlaviyoCore

#if canImport(Testing)
import Testing

struct IdentityTransitionTests {
    struct Case: CustomTestStringConvertible {
        let name: String
        let previous: ProfileData?
        let next: ProfileData
        let expected: IdentityTransition

        var testDescription: String {
            name
        }
    }

    // MARK: - Unchanged

    static let unchangedCases: [Case] = [
        Case(
            name: "same email",
            previous: ProfileData(email: "a@x.com"),
            next: ProfileData(email: "a@x.com"),
            expected: .unchanged
        ),
        Case(
            name: "same identifiers and anonymous ID",
            previous: ProfileData(email: "a@x.com", phoneNumber: "+15555550100", anonymousId: "anon-a"),
            next: ProfileData(email: "a@x.com", phoneNumber: "+15555550100", anonymousId: "anon-a"),
            expected: .unchanged
        ),
        Case(
            name: "same anonymous ID only",
            previous: ProfileData(anonymousId: "anon-a"),
            next: ProfileData(anonymousId: "anon-a"),
            expected: .unchanged
        ),
        Case(
            name: "empty string equals absent",
            previous: ProfileData(email: "", anonymousId: "anon-a"),
            next: ProfileData(phoneNumber: "", anonymousId: "anon-a"),
            expected: .unchanged
        ),
        Case(
            name: "empty email alongside the same external ID",
            previous: ProfileData(email: "", externalId: "external-a"),
            next: ProfileData(externalId: "external-a"),
            expected: .unchanged
        )
    ]

    // MARK: - Shared identifiers, no conflict, and no previous profile

    static let sharedCases: [Case] = [
        Case(
            name: "no previous profile",
            previous: nil,
            next: ProfileData(email: "a@x.com", anonymousId: "anon-a"),
            expected: .initial
        ),
        Case(
            name: "no previous profile, anonymous next",
            previous: nil,
            next: ProfileData(anonymousId: "anon-a"),
            expected: .initial
        ),
        Case(
            name: "same email, new anonymous ID",
            previous: ProfileData(email: "e@x.com", anonymousId: "anon-a"),
            next: ProfileData(email: "e@x.com", anonymousId: "anon-b"),
            expected: .anonymousIdRotated
        ),
        Case(
            name: "enriched with external ID",
            previous: ProfileData(email: "a@x.com"),
            next: ProfileData(email: "a@x.com", externalId: "external-a"),
            expected: .additive
        ),
        Case(
            name: "reduced to email",
            previous: ProfileData(email: "a@x.com", externalId: "external-a"),
            next: ProfileData(email: "a@x.com"),
            expected: .subtractive
        ),
        Case(
            name: "enriched with phone number",
            previous: ProfileData(email: "private@example.com"),
            next: ProfileData(email: "private@example.com", phoneNumber: "+15555550100"),
            expected: .additive
        ),
        Case(
            name: "phone number enriched with email",
            previous: ProfileData(phoneNumber: "+15555550100"),
            next: ProfileData(email: "e@x.com", phoneNumber: "+15555550100"),
            expected: .additive
        ),
        Case(
            name: "empty values beside a shared external ID, enriched",
            previous: ProfileData(email: "", externalId: "external-a"),
            next: ProfileData(email: "", phoneNumber: "+15551234567", externalId: "external-a"),
            expected: .additive
        ),
        Case(
            name: "empty values beside a shared external ID, reduced",
            previous: ProfileData(email: "", phoneNumber: "+15551234567", externalId: "external-a"),
            next: ProfileData(email: "", externalId: "external-a"),
            expected: .subtractive
        )
    ]

    // MARK: - Replacing, clearing and conflicting changes

    static let replacementCases: [Case] = [
        Case(
            name: "anonymous profile gains an email",
            previous: ProfileData(anonymousId: "anon-a"),
            next: ProfileData(email: "e@x.com", anonymousId: "anon-a"),
            expected: .anonymousToIdentified
        ),
        Case(
            name: "different anonymous ID",
            previous: ProfileData(anonymousId: "anon-a"),
            next: ProfileData(anonymousId: "anon-b"),
            expected: .replacement
        ),
        Case(
            name: "different email",
            previous: ProfileData(email: "a@x.com"),
            next: ProfileData(email: "b@x.com"),
            expected: .replacement
        ),
        Case(
            name: "email to phone number with no overlap",
            previous: ProfileData(email: "a@x.com"),
            next: ProfileData(phoneNumber: "+15555550100"),
            expected: .replacement
        ),
        Case(
            name: "same email, different phone number",
            previous: ProfileData(email: "a@x.com", phoneNumber: "+15555550100"),
            next: ProfileData(email: "a@x.com", phoneNumber: "+15555550199"),
            expected: .partialConflict
        ),
        Case(
            name: "same email, different external ID",
            previous: ProfileData(email: "a@x.com", externalId: "external-a"),
            next: ProfileData(email: "a@x.com", externalId: "external-b"),
            expected: .partialConflict
        ),
        Case(
            name: "only the anonymous ID is shared",
            previous: ProfileData(email: "a@x.com", anonymousId: "anonymous-a"),
            next: ProfileData(externalId: "external-b", anonymousId: "anonymous-a"),
            expected: .replacement
        ),
        Case(
            name: "empty values hide all stable overlap",
            previous: ProfileData(email: "", externalId: "external-a"),
            next: ProfileData(email: "", phoneNumber: "+15551234567"),
            expected: .replacement
        ),
        Case(
            name: "empty email does not match a present email",
            previous: ProfileData(email: "a@x.com"),
            next: ProfileData(email: ""),
            expected: .cleared
        ),
        Case(
            name: "email comparison is case-sensitive",
            previous: ProfileData(email: "A@x.com"),
            next: ProfileData(email: "a@x.com"),
            expected: .replacement
        ),
        Case(
            name: "values are not trimmed",
            previous: ProfileData(email: "a@x.com"),
            next: ProfileData(email: " a@x.com"),
            expected: .replacement
        ),
        Case(
            name: "identified profile reset to anonymous",
            previous: ProfileData(email: "a@x.com", anonymousId: "anon-a"),
            next: ProfileData(anonymousId: "anon-b"),
            expected: .cleared
        )
    ]

    static let newTransitionCases: [Case] = [
        Case(
            name: "A becomes A+P",
            previous: ProfileData(email: "a@x.com"),
            next: ProfileData(email: "a@x.com", phoneNumber: "+15555550100"),
            expected: .additive
        ),
        Case(
            name: "A+P becomes A",
            previous: ProfileData(email: "a@x.com", phoneNumber: "+15555550100"),
            next: ProfileData(email: "a@x.com"),
            expected: .subtractive
        ),
        Case(
            name: "A+P becomes A+X",
            previous: ProfileData(email: "a@x.com", phoneNumber: "+15555550100"),
            next: ProfileData(email: "a@x.com", externalId: "external-a"),
            expected: .reshaped
        ),
        Case(
            name: "A+X becomes B+X",
            previous: ProfileData(email: "a@x.com", externalId: "external-a"),
            next: ProfileData(email: "b@x.com", externalId: "external-a"),
            expected: .partialConflict
        ),
        Case(
            name: "A becomes nothing",
            previous: ProfileData(email: "a@x.com"),
            next: ProfileData(),
            expected: .cleared
        ),
        Case(
            name: "anonymous becomes A",
            previous: ProfileData(anonymousId: "anon-a"),
            next: ProfileData(email: "a@x.com"),
            expected: .anonymousToIdentified
        ),
        Case(
            name: "same email, anonymous ID appears",
            previous: ProfileData(email: "a@x.com"),
            next: ProfileData(email: "a@x.com", anonymousId: "anon-a"),
            expected: .anonymousIdRotated
        ),
        Case(
            name: "nil previous, empty next",
            previous: nil,
            next: ProfileData(),
            expected: .initial
        ),
        Case(
            name: "no ids on either side, anonymous ID appears",
            previous: ProfileData(),
            next: ProfileData(anonymousId: "anon-a"),
            expected: .replacement
        )
    ]

    @Test(arguments: unchangedCases + sharedCases + replacementCases + newTransitionCases)
    func classify(_ testCase: Case) {
        let transition = IdentityTransition.classify(previous: testCase.previous, next: testCase.next)
        #expect(transition == testCase.expected)
    }

    // MARK: - discardsAuthToken

    @Test(arguments: [
        (IdentityTransition.initial, false),
        (.unchanged, false),
        (.anonymousToIdentified, true),
        (.cleared, true),
        (.partialConflict, true),
        (.anonymousIdRotated, false),
        (.additive, false),
        (.subtractive, false),
        (.reshaped, false),
        (.replacement, true)
    ])
    func discardsAuthTokenMapping(_ transition: IdentityTransition, _ expected: Bool) {
        #expect(transition.discardsAuthToken == expected)
    }

    // MARK: - Parity with the previous three-case classifier

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

    private static let parityProfiles: [ProfileData] = {
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
        let previousProfiles: [ProfileData?] = [nil] + Self.parityProfiles
        var checked = 0
        for previous in previousProfiles {
            for next in Self.parityProfiles {
                let transition = IdentityTransition.classify(previous: previous, next: next)
                let legacy = Self.legacyClassify(previous: previous, next: next)
                let pair = "\(String(describing: previous)) -> \(next) (new \(transition), legacy \(legacy))"
                #expect(transition.discardsAuthToken == (legacy == .replacement), "discardsAuthToken: \(pair)")
                #expect((transition == .unchanged) == (legacy == .unchanged), "unchanged: \(pair)")
                checked += 1
            }
        }
        #expect(checked == previousProfiles.count * Self.parityProfiles.count)
    }
}
#endif
