//
//  IdentityTransitionTests.swift
//  KlaviyoCore
//
//  Mirrors the identifier-transition cases in onsite-personalization's
//  `tokenStore.test.ts`.
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

    // MARK: - Compatible

    static let compatibleCases: [Case] = [
        Case(
            name: "no previous profile",
            previous: nil,
            next: ProfileData(email: "a@x.com", anonymousId: "anon-a"),
            expected: .compatible
        ),
        Case(
            name: "no previous profile, anonymous next",
            previous: nil,
            next: ProfileData(anonymousId: "anon-a"),
            expected: .compatible
        ),
        Case(
            name: "same email, new anonymous ID",
            previous: ProfileData(email: "e@x.com", anonymousId: "anon-a"),
            next: ProfileData(email: "e@x.com", anonymousId: "anon-b"),
            expected: .compatible
        ),
        Case(
            name: "enriched with external ID",
            previous: ProfileData(email: "a@x.com"),
            next: ProfileData(email: "a@x.com", externalId: "external-a"),
            expected: .compatible
        ),
        Case(
            name: "reduced to email",
            previous: ProfileData(email: "a@x.com", externalId: "external-a"),
            next: ProfileData(email: "a@x.com"),
            expected: .compatible
        ),
        Case(
            name: "enriched with phone number",
            previous: ProfileData(email: "private@example.com"),
            next: ProfileData(email: "private@example.com", phoneNumber: "+15555550100"),
            expected: .compatible
        ),
        Case(
            name: "phone number enriched with email",
            previous: ProfileData(phoneNumber: "+15555550100"),
            next: ProfileData(email: "e@x.com", phoneNumber: "+15555550100"),
            expected: .compatible
        ),
        Case(
            name: "empty values beside a shared external ID, enriched",
            previous: ProfileData(email: "", externalId: "external-a"),
            next: ProfileData(email: "", phoneNumber: "+15551234567", externalId: "external-a"),
            expected: .compatible
        ),
        Case(
            name: "empty values beside a shared external ID, reduced",
            previous: ProfileData(email: "", phoneNumber: "+15551234567", externalId: "external-a"),
            next: ProfileData(email: "", externalId: "external-a"),
            expected: .compatible
        )
    ]

    // MARK: - Replacement

    static let replacementCases: [Case] = [
        Case(
            name: "anonymous profile gains an email",
            previous: ProfileData(anonymousId: "anon-a"),
            next: ProfileData(email: "e@x.com", anonymousId: "anon-a"),
            expected: .replacement
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
            expected: .replacement
        ),
        Case(
            name: "same email, different external ID",
            previous: ProfileData(email: "a@x.com", externalId: "external-a"),
            next: ProfileData(email: "a@x.com", externalId: "external-b"),
            expected: .replacement
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
            expected: .replacement
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
            expected: .replacement
        )
    ]

    @Test(arguments: unchangedCases + compatibleCases + replacementCases)
    func classify(_ testCase: Case) {
        let transition = IdentityTransition.classify(previous: testCase.previous, next: testCase.next)
        #expect(transition == testCase.expected)
    }
}
#endif
