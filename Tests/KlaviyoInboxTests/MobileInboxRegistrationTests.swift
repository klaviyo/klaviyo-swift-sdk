//
//  MobileInboxRegistrationTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoCore
import KlaviyoInboxCore
import KlaviyoInboxTestSupport

#if canImport(Testing)
import Testing

private struct TestSDK: KlaviyoSDKModule {}

/// `.serialized` because the public API tests swap the shared `MobileInboxRegistration.current`.
@Suite(.serialized)
final class MobileInboxRegistrationTests {
    private let temp = InboxTemporaryGroup()
    private let savedCurrent = MobileInboxRegistration.current

    deinit {
        MobileInboxRegistration.current = savedCurrent
        temp.remove()
    }

    private func makeRegistration(group: InboxAppGroup? = nil) -> MobileInboxRegistration {
        MobileInboxRegistration(group: group ?? temp.group)
    }

    private func enablement() -> InboxEnablement {
        InboxConfigStore(group: temp.group).enablement()
    }

    @Test
    func nothingIsWrittenBeforeRegister() {
        _ = makeRegistration()
        #expect(!FileManager.default.fileExists(atPath: temp.root.path))
        #expect(enablement() == .neverRegistered)
    }

    @Test
    func registerEnablesWithConfiguredLimit() {
        makeRegistration().register(MobileInboxConfig(localRetentionLimit: 30))
        #expect(enablement() == .enabled(localRetentionLimit: 30))
    }

    @Test
    func registerAgainOverwritesLimit() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig(localRetentionLimit: 30))
        registration.register(MobileInboxConfig(localRetentionLimit: 60))
        #expect(enablement() == .enabled(localRetentionLimit: 60))
    }

    @Test(arguments: [InboxTemporaryGroup.unreachable, InboxTemporaryGroup.missingIdentifier])
    func registerWithUnavailableGroupPersistsNothing(group: InboxAppGroup) {
        makeRegistration(group: group).register(MobileInboxConfig())
        #expect(!FileManager.default.fileExists(atPath: temp.root.path))
        #expect(enablement() == .neverRegistered)
    }

    @Test
    func unregisterDisables() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig())
        registration.unregister()
        #expect(enablement() == .disabled)
    }

    @Test
    func unregisterAfterRelaunchStillDisables() {
        makeRegistration().register(MobileInboxConfig())
        // A fresh coordinator stands in for a new launch.
        makeRegistration().unregister()
        #expect(enablement() == .disabled)
    }

    @Test
    func unregisterWithoutPriorRegisterIsANoOp() {
        makeRegistration().unregister()
        #expect(!FileManager.default.fileExists(atPath: temp.root.path), "must not create any file or directory")
        #expect(enablement() == .neverRegistered)
    }

    @Test
    func unregisterWhenGroupBecameUnreachableLeavesStateUntouched() {
        makeRegistration().register(MobileInboxConfig(localRetentionLimit: 10))
        makeRegistration(group: InboxTemporaryGroup.unreachable).unregister()
        #expect(enablement() == .enabled(localRetentionLimit: 10))
    }

    @Test
    func registerAfterUnregisterReEnables() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig(localRetentionLimit: 10))
        registration.unregister()
        registration.register(MobileInboxConfig(localRetentionLimit: 10))
        #expect(enablement() == .enabled(localRetentionLimit: 10))
    }

    @Test
    func publicAPIChainsAndReturnsSameType() {
        MobileInboxRegistration.current = makeRegistration()
        let sdk = TestSDK()
        let afterRegister = sdk.registerForMobileInbox(configuration: MobileInboxConfig())
        #expect(type(of: afterRegister) == TestSDK.self)
        #expect(enablement() == .enabled(localRetentionLimit: 100))

        let afterUnregister = afterRegister.unregisterFromMobileInbox()
        #expect(type(of: afterUnregister) == TestSDK.self)
        #expect(enablement() == .disabled)
    }
}
#endif
