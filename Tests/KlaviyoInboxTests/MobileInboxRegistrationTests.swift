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
import XCTest

private struct TestSDK: KlaviyoSDKModule {}

final class MobileInboxRegistrationTests: XCTestCase {
    private var temp: InboxTemporaryGroup!
    private var logs: InboxLogRecorder!
    private var savedCurrent: MobileInboxRegistration!

    override func setUp() {
        super.setUp()
        temp = InboxTemporaryGroup()
        logs = InboxLogRecorder()
        savedCurrent = MobileInboxRegistration.current
    }

    override func tearDown() {
        MobileInboxRegistration.current = savedCurrent
        temp.remove()
        logs = nil
        super.tearDown()
    }

    private func makeRegistration(group: InboxAppGroup? = nil) -> MobileInboxRegistration {
        MobileInboxRegistration(group: group ?? temp.group)
    }

    private func enablement() -> InboxEnablement {
        InboxConfigStore(group: temp.group).enablement()
    }

    func testNothingIsWrittenBeforeRegister() {
        _ = makeRegistration()
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.root.path))
        XCTAssertEqual(enablement(), .neverRegistered)
    }

    func testRegisterEnablesWithConfiguredLimit() {
        makeRegistration().register(MobileInboxConfig(localRetentionLimit: 30))
        XCTAssertEqual(enablement(), .enabled(localRetentionLimit: 30))
    }

    func testRegisterAgainOverwritesLimit() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig(localRetentionLimit: 30))
        registration.register(MobileInboxConfig(localRetentionLimit: 60))
        XCTAssertEqual(enablement(), .enabled(localRetentionLimit: 60))
    }

    func testRegisterWithUnreachableGroupPersistsNothingAndLogs() {
        makeRegistration(group: InboxTemporaryGroup.unreachable)
            .register(MobileInboxConfig())
        XCTAssertEqual(enablement(), .neverRegistered)
        XCTAssertFalse(logs.errors.isEmpty)
    }

    func testRegisterWithoutInfoPlistEntryPersistsNothingAndLogs() {
        makeRegistration(group: InboxTemporaryGroup.missingIdentifier).register(MobileInboxConfig())
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.root.path))
        XCTAssertFalse(logs.errors.isEmpty)
    }

    func testUnregisterDisables() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig())
        registration.unregister()
        XCTAssertEqual(enablement(), .disabled)
    }

    func testUnregisterAfterRelaunchStillDisables() {
        makeRegistration().register(MobileInboxConfig())
        // A fresh coordinator stands in for a new launch.
        makeRegistration().unregister()
        XCTAssertEqual(enablement(), .disabled)
    }

    func testUnregisterWithoutPriorRegisterIsANoOpThatWarns() {
        makeRegistration().unregister()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: temp.root.path),
            "must not create any file or directory"
        )
        XCTAssertEqual(enablement(), .neverRegistered)
        XCTAssertFalse(logs.warnings.isEmpty)
    }

    func testUnregisterWhenGroupBecameUnreachableLogsAndDoesNotCrash() {
        makeRegistration().register(MobileInboxConfig())
        makeRegistration(group: InboxTemporaryGroup.unreachable).unregister()
        XCTAssertFalse(logs.errors.isEmpty)
    }

    func testRegisterAfterUnregisterReEnables() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig(localRetentionLimit: 10))
        registration.unregister()
        registration.register(MobileInboxConfig(localRetentionLimit: 10))
        XCTAssertEqual(enablement(), .enabled(localRetentionLimit: 10))
    }

    func testPublicAPIChainsAndReturnsSameType() {
        MobileInboxRegistration.current = makeRegistration()
        let sdk = TestSDK()
        let configuration = MobileInboxConfig()
        let afterRegister = sdk.registerForMobileInbox(configuration: configuration)
        XCTAssertTrue(type(of: afterRegister) == TestSDK.self)
        XCTAssertEqual(enablement(), .enabled(localRetentionLimit: 100))

        let afterUnregister = afterRegister.unregisterFromMobileInbox()
        XCTAssertTrue(type(of: afterUnregister) == TestSDK.self)
        XCTAssertEqual(enablement(), .disabled)
    }

    func testLoggingFollowsTheSDKWideSwitch() {
        KlaviyoLogConfig.shared.isLoggingEnabled = false
        defer { KlaviyoLogConfig.shared.isLoggingEnabled = true }
        makeRegistration(group: InboxTemporaryGroup.unreachable)
            .register(MobileInboxConfig())
        XCTAssertTrue(logs.errors.isEmpty, "logging disabled must silence Inbox logs too")
    }
}
