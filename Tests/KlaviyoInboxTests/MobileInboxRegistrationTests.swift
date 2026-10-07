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
    private let groupId = "group.com.example.app"
    private var temp: InboxTemporaryGroup!
    private var defaultsSuite: String!
    private var defaults: UserDefaults!
    private var logs: InboxLogRecorder!
    private var savedCurrent: MobileInboxRegistration!

    override func setUp() {
        super.setUp()
        temp = InboxTemporaryGroup()
        defaultsSuite = "klaviyo-inbox-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)
        logs = InboxLogRecorder()
        savedCurrent = MobileInboxRegistration.current
    }

    override func tearDown() {
        MobileInboxRegistration.current = savedCurrent
        defaults.removePersistentDomain(forName: defaultsSuite)
        temp.remove()
        logs = nil
        super.tearDown()
    }

    private func makeRegistration(group: InboxAppGroup? = nil) -> MobileInboxRegistration {
        MobileInboxRegistration(group: group ?? temp.group, defaults: defaults)
    }

    private func enablement() -> InboxEnablement {
        InboxConfigStore(appGroupIdentifier: groupId, group: temp.group).enablement()
    }

    func testNothingIsWrittenBeforeRegister() {
        _ = makeRegistration()
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.root.path))
        XCTAssertEqual(enablement(), .neverRegistered)
    }

    func testRegisterEnablesWithConfiguredLimit() {
        makeRegistration().register(MobileInboxConfig(appGroupIdentifier: groupId, localRetentionLimit: 30))
        XCTAssertEqual(enablement(), .enabled(localRetentionLimit: 30))
        XCTAssertEqual(defaults.string(forKey: MobileInboxRegistration.groupPointerKey), groupId)
    }

    func testRegisterAgainOverwritesLimit() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig(appGroupIdentifier: groupId, localRetentionLimit: 30))
        registration.register(MobileInboxConfig(appGroupIdentifier: groupId, localRetentionLimit: 60))
        XCTAssertEqual(enablement(), .enabled(localRetentionLimit: 60))
    }

    func testRegisterWithUnreachableGroupPersistsNothingAndLogs() {
        makeRegistration(group: InboxTemporaryGroup.unreachable)
            .register(MobileInboxConfig(appGroupIdentifier: groupId))
        XCTAssertNil(defaults.string(forKey: MobileInboxRegistration.groupPointerKey))
        XCTAssertEqual(enablement(), .neverRegistered)
        XCTAssertFalse(logs.errors.isEmpty)
    }

    func testRegisterWithEmptyIdentifierPersistsNothingAndLogs() {
        makeRegistration().register(MobileInboxConfig(appGroupIdentifier: ""))
        XCTAssertNil(defaults.string(forKey: MobileInboxRegistration.groupPointerKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.root.path))
        XCTAssertFalse(logs.errors.isEmpty)
    }

    func testUnregisterDisables() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig(appGroupIdentifier: groupId))
        registration.unregister()
        XCTAssertEqual(enablement(), .disabled)
    }

    func testUnregisterAfterRelaunchStillDisables() {
        makeRegistration().register(MobileInboxConfig(appGroupIdentifier: groupId))
        // A fresh coordinator over the same defaults stands in for a new launch.
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

    func testRegisteringADifferentGroupWarnsAndLeavesThePreviousGroupAlone() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig(appGroupIdentifier: "group.old"))
        XCTAssertTrue(logs.warnings.isEmpty, "the first registration has nothing to warn about")

        registration.register(MobileInboxConfig(appGroupIdentifier: "group.new"))

        XCTAssertEqual(logs.warnings.count, 1)
        XCTAssertTrue(logs.warnings.first?.message.contains("group.old") ?? false)
        XCTAssertEqual(
            InboxConfigStore(appGroupIdentifier: "group.old", group: temp.group).enablement(),
            .enabled(localRetentionLimit: 100),
            "switching groups is unsupported, so the previous group is deliberately not touched"
        )
    }

    func testReRegisteringTheSameGroupDoesNotWarn() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig(appGroupIdentifier: groupId))
        registration.register(MobileInboxConfig(appGroupIdentifier: groupId, localRetentionLimit: 20))
        XCTAssertTrue(logs.warnings.isEmpty)
    }

    func testUnregisterTargetsTheMostRecentlyRegisteredGroup() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig(appGroupIdentifier: "group.old"))
        registration.register(MobileInboxConfig(appGroupIdentifier: "group.new"))
        registration.unregister()
        let newGroup = InboxConfigStore(appGroupIdentifier: "group.new", group: temp.group)
        XCTAssertEqual(newGroup.enablement(), .disabled)
    }

    func testUnregisterWhenGroupBecameUnreachableLogsAndDoesNotCrash() {
        makeRegistration().register(MobileInboxConfig(appGroupIdentifier: groupId))
        makeRegistration(group: InboxTemporaryGroup.unreachable).unregister()
        XCTAssertFalse(logs.errors.isEmpty)
    }

    func testRegisterAfterUnregisterReEnables() {
        let registration = makeRegistration()
        registration.register(MobileInboxConfig(appGroupIdentifier: groupId, localRetentionLimit: 10))
        registration.unregister()
        registration.register(MobileInboxConfig(appGroupIdentifier: groupId, localRetentionLimit: 10))
        XCTAssertEqual(enablement(), .enabled(localRetentionLimit: 10))
    }

    func testPublicAPIChainsAndReturnsSameType() {
        MobileInboxRegistration.current = makeRegistration()
        let sdk = TestSDK()
        let configuration = MobileInboxConfig(appGroupIdentifier: groupId)
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
            .register(MobileInboxConfig(appGroupIdentifier: groupId))
        XCTAssertTrue(logs.errors.isEmpty, "logging disabled must silence Inbox logs too")
    }
}
