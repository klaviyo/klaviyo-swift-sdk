//
//  KlaviyoAppDelegateSwizzlerTests.swift
//  KlaviyoSwiftTests
//
//  Tests for `KlaviyoAppDelegateSwizzler` — both the pure
//  `resolveSwizzleTargetClass(for:)` helper and the runtime-mutating
//  `performSwizzle(on:)` path (exchange, graft, and inherited-IMP).
//
//  Because ObjC method exchanges are permanent within a process, each
//  `performSwizzle` test uses its own unique delegate class so runtime
//  changes from one test cannot affect another.
//

@testable import KlaviyoSwift
import KlaviyoCore
import ObjectiveC.runtime
import UIKit
import XCTest

@MainActor
final class KlaviyoAppDelegateSwizzlerTests: XCTestCase {
    // MARK: - Selectors

    private let originalSelector = #selector(
        UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
    )
    private var swizzledSelector: Selector {
        KlaviyoAppDelegateSwizzler._swizzledSelectorForTesting
    }

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        KlaviyoAppDelegateSwizzler._resetStateForTesting()
    }

    override func tearDown() async throws {
        KlaviyoAppDelegateSwizzler._resetStateForTesting()
        try await super.tearDown()
    }

    // MARK: - Test doubles: resolveSwizzleTargetClass

    private final class DirectAppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {}
    }

    private final class ForwardingProxyDelegate: NSObject, UIApplicationDelegate {
        let inner: DirectAppDelegate
        init(inner: DirectAppDelegate) { self.inner = inner }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            inner.responds(to: aSelector) ? inner : super.forwardingTarget(for: aSelector)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || inner.responds(to: aSelector)
        }
    }

    private final class OpaqueDelegate: NSObject, UIApplicationDelegate {}

    /// Base class that owns the device-token method.
    private class BaseAppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {}
    }

    /// Subclass that only inherits the method from `BaseAppDelegate` without overriding it.
    private final class SubclassAppDelegate: BaseAppDelegate {}

    // MARK: - Test doubles: performSwizzle (unique per test — ObjC changes are permanent)

    /// Exchange path: class declares the selector in its own IMP table.
    private class ExchangeDelegate: NSObject, UIApplicationDelegate {
        var hostCallCount = 0
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {
            hostCallCount += 1
        }
    }

    /// Graft path: class has no implementation — donor is added without forwarding.
    private class GraftDelegate: NSObject, UIApplicationDelegate {}

    /// Inherited path: base owns the method; sub inherits without overriding.
    private class InheritedBaseDelegate: NSObject, UIApplicationDelegate {
        var hostCallCount = 0
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {
            hostCallCount += 1
        }
    }

    private class InheritedSubDelegate: InheritedBaseDelegate {}

    /// Exchange path — used only by testDonorIMPForwardsToHostOriginalAfterExchange.
    /// Separate from ExchangeDelegate because ObjC swizzle changes are permanent per class.
    private class ExchangeForwardingDelegate: NSObject, UIApplicationDelegate {
        var hostCallCount = 0
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {
            hostCallCount += 1
        }
    }

    /// Inherited path — base used only by testDonorIMPForwardsToInheritedOriginalAfterGraftOnSubclass.
    private class InheritedForwardingBaseDelegate: NSObject, UIApplicationDelegate {
        var hostCallCount = 0
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {
            hostCallCount += 1
        }
    }

    private class InheritedForwardingSubDelegate: InheritedForwardingBaseDelegate {}

    /// Separate class used only for the idempotency test.
    private class IdempotencyDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {}
    }

    private class MultipleInstallFirstDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {}
    }

    private class MultipleInstallSecondDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {}
    }

    /// Parent-first installation path: after the parent is instrumented, the child inherits
    /// Klaviyo's donor IMP. Installing the child must continue forwarding to this host method.
    private class ParentFirstBaseDelegate: NSObject, UIApplicationDelegate {
        var hostCallCount = 0
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {
            hostCallCount += 1
        }
    }

    private class ParentFirstSubDelegate: ParentFirstBaseDelegate {}

    // MARK: - Helpers

    /// Returns true if `cls` declares `selector` in its own method table (not via superclass).
    private func classOwnsMethod(_ cls: AnyClass, selector: Selector) -> Bool {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { return false }
        defer { free(methods) }
        return (0..<Int(count)).contains { method_getName(methods[$0]) == selector }
    }

    /// Returns the IMP at `selector` on `cls`, failing the test if the method is absent.
    private func imp(on cls: AnyClass, selector: Selector) -> IMP? {
        guard let method = class_getInstanceMethod(cls, selector) else {
            XCTFail("No method at \(NSStringFromSelector(selector)) on \(cls)")
            return nil
        }
        return method_getImplementation(method)
    }

    /// Skips the test if `cls` was already swizzled in a prior repetition.
    ///
    /// ObjC runtime method additions and exchanges are permanent for the lifetime of the
    /// process. Xcode's test-repetition feature reruns tests in the same process, so
    /// repetition N+1 sees already-mutated classes. `_resetStateForTesting()` resets the
    /// logical gate but cannot undo ObjC changes — a second swizzle on the same class
    /// produces incorrect IMP state. Skipping is the correct response: the test is not
    /// flaky, it simply cannot be repeated in-process.
    private func skipIfAlreadySwizzled(_ cls: AnyClass) throws {
        let donorIMP = imp(on: KlaviyoAppDelegateSwizzler.self, selector: swizzledSelector)
        let currentIMP = class_getInstanceMethod(cls, originalSelector).map(method_getImplementation)
        try XCTSkipIf(
            currentIMP == donorIMP,
            "\(cls) was already swizzled in a prior repetition — ObjC changes are permanent per process"
        )
    }

    // MARK: - resolveSwizzleTargetClass tests

    // App delegate directly implements `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    // Resolver must return the delegate's own class with no forwarding probe needed.
    func testResolveTargetDirectImplementor() {
        let delegate = DirectAppDelegate()
        XCTAssertTrue(KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: delegate) == DirectAppDelegate.self)
    }

    // SwiftUI `@UIApplicationDelegateAdaptor` pattern: the visible delegate is a proxy that
    // has no IMP of its own but forwards the selector to an inner real delegate via
    // `-forwardingTargetForSelector:`. Resolver must follow the forwarding chain and return
    // the inner class so we swizzle the class that actually runs the method.
    func testResolveTargetForwardingProxy() {
        let inner = DirectAppDelegate()
        let proxy = ForwardingProxyDelegate(inner: inner)

        XCTAssertNil(
            class_getInstanceMethod(ForwardingProxyDelegate.self, originalSelector),
            "Proxy class must not have the method in its IMP table"
        )
        XCTAssertTrue(
            proxy.responds(to: originalSelector),
            "Proxy must respond via forwarding for this test to be meaningful"
        )

        let resolved: AnyClass = KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: proxy)
        XCTAssertTrue(resolved == DirectAppDelegate.self)
    }

    // Delegate implements no device-token method and has no forwarding target. Resolver must
    // fall back to the delegate's own class so `performSwizzle` can graft the donor IMP onto it.
    func testResolveTargetOpaqueDelegate() {
        let opaque = OpaqueDelegate()
        let resolved: AnyClass = KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: opaque)
        XCTAssertTrue(resolved == OpaqueDelegate.self)
    }

    // Delegate subclass inherits the method from its superclass but doesn't override it.
    // Resolver must return the subclass (not the superclass) so `performSwizzle` targets the
    // concrete runtime type and uses the inherited-graft path rather than mutating the superclass.
    func testResolveTargetSubclassWithInheritedMethod() {
        let delegate = SubclassAppDelegate()

        XCTAssertNotNil(
            class_getInstanceMethod(SubclassAppDelegate.self, originalSelector),
            "Precondition: method must be reachable via superclass chain"
        )
        XCTAssertFalse(
            classOwnsMethod(SubclassAppDelegate.self, selector: originalSelector),
            "Precondition: subclass must not own the method"
        )

        let resolved: AnyClass = KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: delegate)
        XCTAssertTrue(resolved == SubclassAppDelegate.self)
    }

    // MARK: - performSwizzle tests

    // Host class owns the device-token method in its own IMP table (most common case).
    // Swizzler must exchange IMPs so `originalSelector` points to the donor and `swizzledSelector`
    // holds the host's original, and must record the class in `swappedClasses` so the donor
    // knows to forward after calling `KlaviyoSDK().set(pushToken:)`.
    func testExchangePathSwapsIMPOnHostClass() throws {
        try skipIfAlreadySwizzled(ExchangeDelegate.self)
        // ExchangeDelegate owns the method — swizzler must exchange IMPs on the class itself.
        let donorMethod = class_getInstanceMethod(
            KlaviyoAppDelegateSwizzler.self, swizzledSelector
        )!
        let donorIMP = method_getImplementation(donorMethod)

        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: ExchangeDelegate.self)

        // originalSelector now holds the donor IMP.
        let installedMethod = class_getInstanceMethod(ExchangeDelegate.self, originalSelector)!
        XCTAssertEqual(method_getImplementation(installedMethod), donorIMP)

        // swappedClasses must record ExchangeDelegate so the donor knows to forward.
        XCTAssertTrue(KlaviyoAppDelegateSwizzler._isSwappedForTesting(ObjectIdentifier(ExchangeDelegate.self)))
    }

    // Host class has no device-token method at all — neither owned nor inherited. Swizzler
    // must add the donor IMP directly under `originalSelector` with no forwarding setup, and
    // must NOT record the class in `swappedClasses` (donor would recurse if it tried to forward).
    func testGraftPathAddsIMPWithoutForwarding() throws {
        try skipIfAlreadySwizzled(GraftDelegate.self)
        // GraftDelegate has no implementation — swizzler must graft without marking as swapped.
        XCTAssertFalse(
            classOwnsMethod(GraftDelegate.self, selector: originalSelector),
            "Precondition: class must not have the method before swizzle"
        )

        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: GraftDelegate.self)

        XCTAssertTrue(
            classOwnsMethod(GraftDelegate.self, selector: originalSelector),
            "Donor IMP must be added to the class after graft"
        )
        // No swap recorded — donor IMP checks this to avoid infinite recursion.
        XCTAssertFalse(KlaviyoAppDelegateSwizzler._isSwappedForTesting(ObjectIdentifier(GraftDelegate.self)))
    }

    // Host subclass inherits the method from its superclass without overriding it. Swizzler
    // must graft the donor onto the subclass only — `originalSelector` and `swizzledSelector`
    // are added to the subclass's own IMP table, and the superclass method table must remain
    // byte-for-byte unchanged. This prevents other subclasses and direct superclass instances
    // from having their behavior altered as a side effect of our swizzle.
    func testInheritedPathGraftsOnSubclassLeavingSuperclassUnchanged() throws {
        try skipIfAlreadySwizzled(InheritedSubDelegate.self)
        // Capture the superclass IMP before swizzle.
        let baseMethod = class_getInstanceMethod(InheritedBaseDelegate.self, originalSelector)!
        let baseIMPBefore = method_getImplementation(baseMethod)

        XCTAssertFalse(
            classOwnsMethod(InheritedSubDelegate.self, selector: originalSelector),
            "Precondition: subclass must not own the method"
        )

        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: InheritedSubDelegate.self)

        // Superclass IMP must be unchanged.
        let baseIMPAfter = method_getImplementation(
            class_getInstanceMethod(InheritedBaseDelegate.self, originalSelector)!
        )
        XCTAssertEqual(baseIMPBefore, baseIMPAfter, "Superclass method table must not be mutated")

        // Subclass must now own the original selector while retaining the exact inherited IMP.
        XCTAssertTrue(
            classOwnsMethod(InheritedSubDelegate.self, selector: originalSelector),
            "Subclass must own originalSelector after graft"
        )
        XCTAssertEqual(
            KlaviyoAppDelegateSwizzler._priorIMPForTesting(InheritedSubDelegate.self),
            baseIMPBefore
        )

        // Swap recorded so the donor knows to forward to the inherited IMP.
        XCTAssertTrue(
            KlaviyoAppDelegateSwizzler._isSwappedForTesting(ObjectIdentifier(InheritedSubDelegate.self))
        )
    }

    // The per-class entry must retain the exact host IMP that was active before installation.
    func testDonorRetainsHostOriginalIMP() throws {
        try skipIfAlreadySwizzled(ExchangeForwardingDelegate.self)
        let hostIMPBefore = imp(on: ExchangeForwardingDelegate.self, selector: originalSelector)

        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: ExchangeForwardingDelegate.self)

        XCTAssertEqual(
            KlaviyoAppDelegateSwizzler._priorIMPForTesting(ExchangeForwardingDelegate.self),
            hostIMPBefore,
            "The exact immediately prior host IMP must be retained"
        )
    }

    // The inherited-graft path must retain the base IMP without altering the base class.
    func testDonorRetainsInheritedOriginalAfterGraftOnSubclass() throws {
        try skipIfAlreadySwizzled(InheritedForwardingSubDelegate.self)
        let inheritedIMPBefore = imp(on: InheritedForwardingBaseDelegate.self, selector: originalSelector)

        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: InheritedForwardingSubDelegate.self)

        XCTAssertEqual(
            KlaviyoAppDelegateSwizzler._priorIMPForTesting(InheritedForwardingSubDelegate.self),
            inheritedIMPBefore,
            "The exact inherited IMP must be retained"
        )
    }

    // `swizzleIfPossible` can be called more than once (e.g. host calls `initialize` twice).
    // Only the first call must install the donor IMP; subsequent calls must be no-ops that
    // leave the IMP pointer and method table unchanged.
    func testSwizzleIsIdempotentWithinSingleClaim() throws {
        try skipIfAlreadySwizzled(IdempotencyDelegate.self)
        // First swizzle installs the donor IMP at originalSelector.
        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: IdempotencyDelegate.self)
        let impAfterFirst = method_getImplementation(
            class_getInstanceMethod(IdempotencyDelegate.self, originalSelector)!
        )

        // Second call — claimSwizzle() returns false, performSwizzle must be a no-op.
        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: IdempotencyDelegate.self)
        let impAfterSecond = method_getImplementation(
            class_getInstanceMethod(IdempotencyDelegate.self, originalSelector)!
        )

        XCTAssertEqual(impAfterFirst, impAfterSecond, "Second swizzle call must leave IMP unchanged")
    }

    func testDistinctDelegateClassesEachCaptureTheirImmediatelyPriorIMP() throws {
        try skipIfAlreadySwizzled(MultipleInstallFirstDelegate.self)
        try skipIfAlreadySwizzled(MultipleInstallSecondDelegate.self)
        let firstPrior = imp(on: MultipleInstallFirstDelegate.self, selector: originalSelector)
        let secondPrior = imp(on: MultipleInstallSecondDelegate.self, selector: originalSelector)

        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: MultipleInstallFirstDelegate.self)
        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: MultipleInstallSecondDelegate.self)

        XCTAssertTrue(KlaviyoAppDelegateSwizzler._isInstalledForTesting(MultipleInstallFirstDelegate.self))
        XCTAssertTrue(KlaviyoAppDelegateSwizzler._isInstalledForTesting(MultipleInstallSecondDelegate.self))
        XCTAssertEqual(
            KlaviyoAppDelegateSwizzler._priorIMPForTesting(MultipleInstallFirstDelegate.self),
            firstPrior
        )
        XCTAssertEqual(
            KlaviyoAppDelegateSwizzler._priorIMPForTesting(MultipleInstallSecondDelegate.self),
            secondPrior
        )
    }

    func testInstallingSubclassAfterParentForwardsOnceToOriginalHostImplementation() throws {
        try skipIfAlreadySwizzled(ParentFirstBaseDelegate.self)
        let originalHostIMP = imp(on: ParentFirstBaseDelegate.self, selector: originalSelector)

        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: ParentFirstBaseDelegate.self)
        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: ParentFirstSubDelegate.self)

        guard !KlaviyoAppDelegateSwizzler._isInstalledForTesting(ParentFirstSubDelegate.self) else {
            XCTFail("A subclass inheriting Klaviyo's donor must not capture the donor as its prior IMP")
            return
        }
        XCTAssertEqual(
            KlaviyoAppDelegateSwizzler._priorIMPForTesting(ParentFirstSubDelegate.self),
            originalHostIMP
        )
    }
}
