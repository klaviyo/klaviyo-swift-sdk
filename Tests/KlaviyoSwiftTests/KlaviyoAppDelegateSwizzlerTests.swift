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

    // MARK: - Helpers

    /// Returns true if `cls` declares `selector` in its own method table (not via superclass).
    private func classOwnsMethod(_ cls: AnyClass, selector: Selector) -> Bool {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { return false }
        defer { free(methods) }
        return (0..<Int(count)).contains { method_getName(methods[$0]) == selector }
    }

    /// Invokes the IMP currently installed at `originalSelector` on the delegate's class.
    private func callInstalledIMP(on delegate: NSObject, token: Data = Data([0xAA, 0xBB])) {
        guard let method = class_getInstanceMethod(type(of: delegate), originalSelector) else { return }
        typealias TokenIMP = @convention(c) (NSObject, Selector, UIApplication, NSData) -> Void
        let imp = unsafeBitCast(method_getImplementation(method), to: TokenIMP.self)
        imp(delegate, originalSelector, UIApplication.shared, token as NSData)
    }

    // MARK: - resolveSwizzleTargetClass tests

    func testResolveTargetDirectImplementor() {
        let delegate = DirectAppDelegate()
        XCTAssertTrue(KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: delegate) == DirectAppDelegate.self)
    }

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

        let resolved = KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: proxy)
        XCTAssertTrue(resolved == DirectAppDelegate.self)
    }

    func testResolveTargetOpaqueDelegate() {
        let opaque = OpaqueDelegate()
        let resolved = KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: opaque)
        XCTAssertTrue(resolved == OpaqueDelegate.self)
    }

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

        let resolved = KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: delegate)
        XCTAssertTrue(resolved == SubclassAppDelegate.self)
    }

    // MARK: - performSwizzle tests

    func testExchangePathSwapsIMPOnHostClass() {
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

    func testGraftPathAddsIMPWithoutForwarding() {
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

    func testInheritedPathGraftsOnSubclassLeavingSuperclassUnchanged() {
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

        // Subclass must now own both selectors in its own method table.
        XCTAssertTrue(
            classOwnsMethod(InheritedSubDelegate.self, selector: originalSelector),
            "Subclass must own originalSelector after graft"
        )
        XCTAssertTrue(
            classOwnsMethod(InheritedSubDelegate.self, selector: swizzledSelector),
            "Subclass must own swizzledSelector after graft"
        )

        // Swap recorded so the donor knows to forward to the inherited IMP.
        XCTAssertTrue(
            KlaviyoAppDelegateSwizzler._isSwappedForTesting(ObjectIdentifier(InheritedSubDelegate.self))
        )
    }

    func testDonorIMPForwardsToHostOriginalAfterExchange() {
        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: ExchangeForwardingDelegate.self)

        let delegate = ExchangeForwardingDelegate()
        // Calling through the donor IMP (installed at originalSelector) must chain
        // to the host's original, incrementing its counter.
        callInstalledIMP(on: delegate)

        XCTAssertEqual(delegate.hostCallCount, 1, "Donor IMP must forward to host's original implementation")
    }

    func testDonorIMPForwardsToInheritedOriginalAfterGraftOnSubclass() {
        KlaviyoAppDelegateSwizzler._performSwizzleForTesting(on: InheritedForwardingSubDelegate.self)

        let delegate = InheritedForwardingSubDelegate()
        callInstalledIMP(on: delegate)

        XCTAssertEqual(delegate.hostCallCount, 1, "Donor IMP must forward to the inherited base implementation")
    }

    func testSwizzleIsIdempotentWithinSingleClaim() {
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
}
