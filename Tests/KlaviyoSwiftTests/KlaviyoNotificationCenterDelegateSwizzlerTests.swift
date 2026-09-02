@testable import KlaviyoSwift
import ObjectiveC.runtime
import XCTest

@MainActor
final class KlaviyoNotificationCenterDelegateSwizzlerTests: XCTestCase {
    private final class SetterFixture: NSObject {
        @objc dynamic var delegate: AnyObject?
    }

    private final class HostDelegate: NSObject, UNUserNotificationCenterDelegate {}

    /// Non-final so `SetterFixtureChild` can inherit its swizzled setter without overriding it.
    private class SetterFixtureBase: NSObject {
        @objc dynamic var delegate: AnyObject?
    }

    private final class SetterFixtureChild: SetterFixtureBase {}

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

    /// A subclass that never overrides the setter shares the base class's method table entry.
    /// `priorIMP(for:)` must walk up to the base's recorded entry rather than finding none.
    func testPriorIMPResolvesThroughSuperclassWhenSubclassNeverInstalled() throws {
        let selector = NSSelectorFromString("setDelegate:")
        let basePriorIMP = try method_getImplementation(
            XCTUnwrap(class_getInstanceMethod(SetterFixtureBase.self, selector))
        )

        KlaviyoNotificationCenterDelegateSwizzler._performInstallForTesting(on: SetterFixtureBase.self)

        XCTAssertEqual(
            KlaviyoNotificationCenterDelegateSwizzler._priorIMPForTesting(SetterFixtureChild.self),
            basePriorIMP,
            "the subclass has no entry of its own; lookup must walk to the base class's"
        )
    }

    /// After the base class is installed, the subclass's method table already carries the
    /// donor IMP through inheritance even though the subclass itself was never claimed. A
    /// second install attempt on the subclass must not record that donor IMP as its own
    /// "prior" setter — doing so would make the donor call itself and recurse without bound.
    func testInstallOnSubclassAfterBaseDoesNotRecordDonorAsItsOwnPrior() throws {
        let selector = NSSelectorFromString("setDelegate:")
        KlaviyoNotificationCenterDelegateSwizzler._performInstallForTesting(on: SetterFixtureBase.self)
        let donorIMP = try method_getImplementation(
            XCTUnwrap(class_getInstanceMethod(SetterFixtureBase.self, selector))
        )

        KlaviyoNotificationCenterDelegateSwizzler._performInstallForTesting(on: SetterFixtureChild.self)

        XCTAssertNotEqual(
            KlaviyoNotificationCenterDelegateSwizzler._priorIMPForTesting(SetterFixtureChild.self),
            donorIMP,
            "the donor IMP must never be recorded as its own forwarding target"
        )
    }
}
