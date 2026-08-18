@testable import KlaviyoSwift
import UIKit
import XCTest

@MainActor
final class KlaviyoAutomaticPushInstallerTests: XCTestCase {
    private final class AppDelegateFixture: NSObject, UIApplicationDelegate {}

    override func setUp() {
        super.setUp()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    func testInstallerHonorsAllIndependentFlagCombinations() {
        let combinations: [(open: Bool, token: Bool)] = [
            (false, false),
            (true, false),
            (false, true),
            (true, true)
        ]

        for combination in combinations {
            let center = MockNotificationCenter()
            let delegate = AppDelegateFixture()
            var notificationHookCount = 0
            var tokenHookDelegates: [AnyObject?] = []
            klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { combination.open }
            klaviyoSwiftEnvironment.isAutomaticPushTokenForwardingEnabled = { combination.token }
            klaviyoSwiftEnvironment.notificationCenter = { center }
            klaviyoSwiftEnvironment.installNotificationDelegateHook = {
                notificationHookCount += 1
            }
            klaviyoSwiftEnvironment.installApplicationDelegateTokenHook = {
                tokenHookDelegates.append($0)
            }

            KlaviyoAutomaticPushInstaller.install(for: delegate)

            let context = "open=\(combination.open), token=\(combination.token)"
            XCTAssertEqual(notificationHookCount, combination.open ? 1 : 0, context)
            XCTAssertEqual(tokenHookDelegates.count, combination.token ? 1 : 0, context)
            if combination.open {
                XCTAssertTrue(center.delegate === KlaviyoNotificationDelegate.shared, context)
            } else {
                XCTAssertNil(center.delegate, context)
            }
            if combination.token {
                XCTAssertTrue(tokenHookDelegates.first! === delegate, context)
            }
        }
    }

    func testInstallerHasStableObjectiveCClassAndSelectorNames() {
        XCTAssertEqual(NSStringFromClass(KlaviyoAutomaticPushInstaller.self), "KlaviyoAutomaticPushInstaller")
        XCTAssertTrue(
            KlaviyoAutomaticPushInstaller.responds(
                to: NSSelectorFromString("installForApplicationDelegate:")
            )
        )
    }
}
