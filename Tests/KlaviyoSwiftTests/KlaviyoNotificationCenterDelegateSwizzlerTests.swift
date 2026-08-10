@testable import KlaviyoSwift
import ObjectiveC.runtime
import XCTest

@MainActor
final class KlaviyoNotificationCenterDelegateSwizzlerTests: XCTestCase {
    private final class SetterFixture: NSObject {
        @objc dynamic var delegate: AnyObject?
    }

    private final class HostDelegate: NSObject, UNUserNotificationCenterDelegate {}

    override func setUp() {
        super.setUp()
        KlaviyoNotificationCenterDelegateSwizzler._resetStateForTesting()
    }

    func testInstallCapturesExactPriorSetterAndIsIdempotent() throws {
        let selector = NSSelectorFromString("setDelegate:")
        let priorMethod = try XCTUnwrap(class_getInstanceMethod(SetterFixture.self, selector))
        let priorIMP = method_getImplementation(priorMethod)

        KlaviyoNotificationCenterDelegateSwizzler._performInstallForTesting(on: SetterFixture.self)
        let installedOnce = try method_getImplementation(
            XCTUnwrap(class_getInstanceMethod(SetterFixture.self, selector))
        )
        KlaviyoNotificationCenterDelegateSwizzler._performInstallForTesting(on: SetterFixture.self)
        let installedTwice = try method_getImplementation(
            XCTUnwrap(class_getInstanceMethod(SetterFixture.self, selector))
        )

        XCTAssertEqual(
            KlaviyoNotificationCenterDelegateSwizzler._priorIMPForTesting(SetterFixture.self),
            priorIMP
        )
        XCTAssertEqual(installedOnce, installedTwice)
        XCTAssertNotEqual(installedOnce, priorIMP)
    }

    func testInstalledSetterRestoresProxyAfterHostAssignment() {
        let fixture = SetterFixture()
        let hostDelegate = HostDelegate()

        KlaviyoNotificationCenterDelegateSwizzler._performInstallForTesting(on: SetterFixture.self)
        fixture.delegate = hostDelegate

        XCTAssertTrue(fixture.delegate === KlaviyoNotificationDelegate.shared)
    }
}
