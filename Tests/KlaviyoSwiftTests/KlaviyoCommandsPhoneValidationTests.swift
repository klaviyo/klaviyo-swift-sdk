//
//  KlaviyoCommandsPhoneValidationTests.swift
//  KlaviyoSwiftTests
//
//  Coverage for client-side phone number validation in `KlaviyoCommands`
//  (`setPhoneNumber` and `enqueueProfile`). See `PhoneNumberValidator` for the rules.

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Foundation
import XCTest

class KlaviyoCommandsPhoneValidationTests: KlaviyoBaseTestCase {
    private var warnings: [String] = []

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        LifecycleState.shared.reset()
        warnings = []
        environment.emitDeveloperWarning = { [weak self] in self?.warnings.append($0) }
    }

    // MARK: - setPhoneNumber

    /// Invalid numbers (no country code, too short, letters) are rejected: warning emitted, identity
    /// untouched, nothing enqueued. `21` is the value from MAGE-1384 the server accepted but dropped.
    @MainActor
    func testSetPhoneNumberInvalidFormatIsRejectedWithWarning() {
        seedPostInitWithToken()
        let readQueue = seedTestQueueStore()
        let invalidNumbers = ["21", "8005551234", "+1", "+1800abc1234"]

        invalidNumbers.forEach { KlaviyoCommands.setPhoneNumber($0) }

        XCTAssertNil(IdentityStore.shared.current.phoneNumber)
        XCTAssertTrue(readQueue().isEmpty, "invalid phone must not enqueue any request")
        XCTAssertEqual(warnings.count, invalidNumbers.count)
        XCTAssertTrue(warnings.allSatisfy { $0 == PhoneNumberValidator.invalidFormatWarning })
    }

    /// A rejected number must not clobber a previously valid one.
    @MainActor
    func testSetPhoneNumberInvalidFormatKeepsExistingValidNumber() {
        seedPostInitWithToken(phoneNumber: "+18005551234")
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setPhoneNumber("21")

        XCTAssertEqual(IdentityStore.shared.current.phoneNumber, "+18005551234")
        XCTAssertTrue(readQueue().isEmpty)
    }

    /// Formatted-but-valid numbers are accepted and stored trimmed.
    @MainActor
    func testSetPhoneNumberAcceptsFormattedE164() {
        seedPostInitWithToken()
        _ = seedTestQueueStore()

        KlaviyoCommands.setPhoneNumber("  +1 (800) 555-1234  ")

        XCTAssertEqual(IdentityStore.shared.current.phoneNumber, "+1 (800) 555-1234")
        XCTAssertTrue(warnings.isEmpty)
    }

    // MARK: - enqueueProfile

    /// An invalid phone on a Profile is dropped (with a warning) but the rest of the profile still syncs.
    @MainActor
    func testEnqueueProfileInvalidPhoneIsDroppedButProfileStillSyncs() {
        seedProfileSyncState()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.enqueueProfile(Profile(email: "new@x.com", phoneNumber: "21"))

        XCTAssertNil(IdentityStore.shared.current.phoneNumber)
        XCTAssertEqual(IdentityStore.shared.current.email, "new@x.com")
        XCTAssertTrue(warnings.contains(PhoneNumberValidator.invalidFormatWarning))
        guard case let .createProfile(_, payload) = readQueue().first?.endpoint else {
            return XCTFail("expected createProfile")
        }
        XCTAssertNil(payload.data.attributes.phoneNumber, "invalid phone must not be sent to the API")
        XCTAssertEqual(payload.data.attributes.email, "new@x.com")
    }

    /// A valid E.164 phone on a Profile is persisted and sent.
    @MainActor
    func testEnqueueProfileValidPhoneIsPersistedAndSent() {
        seedProfileSyncState()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.enqueueProfile(Profile(phoneNumber: "+18005551234"))

        XCTAssertEqual(IdentityStore.shared.current.phoneNumber, "+18005551234")
        guard case let .createProfile(_, payload) = readQueue().first?.endpoint else {
            return XCTFail("expected createProfile")
        }
        XCTAssertEqual(payload.data.attributes.phoneNumber, "+18005551234")
    }

    // MARK: - Helpers

    /// Post-init with an anonymous identity and no push token, so `enqueueProfile` enqueues `createProfile`.
    private func seedProfileSyncState() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-old"))
        IdentityStore.shared.updatePushToken(nil)
        markSessionInitialized()
    }
}
