//
//  AuthIdentityTransitionTests.swift
//  KlaviyoSwiftTests
//

@testable import KlaviyoSwift
import KlaviyoCore
import XCTest

final class AuthIdentityTransitionTests: XCTestCase {
    @MainActor
    func testProfileIdentifierContinuityControlsAuthInvalidation() async {
        environment = KlaviyoEnvironment.test()
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let transitions: [(String, Profile, Profile, Bool)] = [
            ("same identifiers", Profile(email: "a@example.com"), Profile(email: "a@example.com"), false),
            ("add external ID", Profile(email: "a@example.com"), Profile(email: "a@example.com", externalId: "external-a"), false),
            ("remove external ID", Profile(email: "a@example.com", externalId: "external-a"), Profile(email: "a@example.com"), false),
            ("replace email", Profile(email: "a@example.com"), Profile(email: "b@example.com"), true),
            ("conflict despite matching external ID", Profile(email: "a@example.com", externalId: "external-a"), Profile(email: "b@example.com", externalId: "external-a"), true),
            ("no shared identifier", Profile(email: "a@example.com"), Profile(phoneNumber: "+15555550100"), true),
            ("clear identifiers", Profile(email: "a@example.com"), Profile(), true),
            ("identify anonymous profile", Profile(), Profile(email: "a@example.com"), true)
        ]

        for (name, previous, incoming, shouldInvalidate) in transitions {
            var state = KlaviyoState(
                apiKey: "company",
                email: previous.email,
                anonymousId: "anonymous",
                phoneNumber: previous.phoneNumber,
                externalId: previous.externalId,
                queue: [],
                initalizationState: .initialized
            )
            let revision = AuthTokenCommandQueue.shared.revision

            _ = KlaviyoReducer().reduce(into: &state, action: .enqueueProfile(incoming))

            XCTAssertEqual(AuthTokenCommandQueue.shared.revision - revision, shouldInvalidate ? 1 : 0, name)
            await AuthTokenCommandQueue.shared.waitForPendingCommands()
        }
    }

    @MainActor
    func testDirectIdentifierSettersUseTheSameAuthContinuityRule() async {
        environment = KlaviyoEnvironment.test()
        await AuthTokenCommandQueue.shared.waitForPendingCommands()

        let transitions: [(String, String?, String?, KlaviyoAction, Bool)] = [
            ("identify anonymous profile", nil, nil, .setEmail("a@example.com"), true),
            ("replace email", "a@example.com", nil, .setEmail("b@example.com"), true),
            ("add external ID with matching email", "a@example.com", nil, .setExternalId("external-a"), false),
            ("replace external ID despite matching email", "a@example.com", "external-a", .setExternalId("external-b"), true),
            ("keep same email", "a@example.com", nil, .setEmail("a@example.com"), false),
            ("ignore blank identifier", "a@example.com", nil, .setPhoneNumber("  "), false)
        ]

        for (name, email, externalId, action, shouldInvalidate) in transitions {
            var state = KlaviyoState(
                apiKey: "company",
                email: email,
                anonymousId: "anonymous",
                externalId: externalId,
                queue: [],
                initalizationState: .initialized
            )
            let revision = AuthTokenCommandQueue.shared.revision

            _ = KlaviyoReducer().reduce(into: &state, action: action)

            XCTAssertEqual(AuthTokenCommandQueue.shared.revision - revision, shouldInvalidate ? 1 : 0, name)
            await AuthTokenCommandQueue.shared.waitForPendingCommands()
        }
    }
}
