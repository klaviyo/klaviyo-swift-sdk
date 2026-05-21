//
//  KlaviyoAppDelegateSwizzlerTests.swift
//  KlaviyoSwiftTests
//
//  Coverage for `KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for:)` — specifically
//  the SwiftUI `@UIApplicationDelegateAdaptor` case where `UIApplication.shared.delegate` is
//  a private SwiftUI wrapper that forwards selectors to the host's real AppDelegate via
//  `-forwardingTargetForSelector:`.
//

@testable import KlaviyoSwift
import ObjectiveC.runtime
import UIKit
import XCTest

@MainActor
final class KlaviyoAppDelegateSwizzlerTests: XCTestCase {
    // MARK: - Test doubles

    /// A direct UIApplicationDelegate implementor — mimics the simplest host case where the
    /// user's `AppDelegate` is the actual `UIApplication.shared.delegate`.
    private final class DirectAppDelegate: NSObject, UIApplicationDelegate {
        var receivedTokens: [Data] = []
        func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            receivedTokens.append(deviceToken)
        }
    }

    /// A NSObject that doesn't implement `application:didRegister...` in its IMP table but
    /// forwards selectors to an inner host delegate via `-forwardingTargetForSelector:`.
    /// This mirrors how SwiftUI's `@UIApplicationDelegateAdaptor` wrapper behaves.
    private final class ForwardingProxyDelegate: NSObject, UIApplicationDelegate {
        let inner: DirectAppDelegate

        init(inner: DirectAppDelegate) {
            self.inner = inner
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            // Mirrors SwiftUI's wrapper: any UIApplicationDelegate selector that the wrapper
            // doesn't implement directly forwards to the inner host AppDelegate.
            if inner.responds(to: aSelector) {
                return inner
            }
            return super.forwardingTarget(for: aSelector)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            // The Obj-C runtime's optional-protocol-method check uses `respondsToSelector:`.
            // SwiftUI's wrapper also overrides this so that selectors implemented by the
            // inner AppDelegate are reported as responded-to.
            return super.responds(to: aSelector) || inner.responds(to: aSelector)
        }
    }

    /// A NSObject that doesn't implement the method and doesn't expose a forwarding target.
    /// Mirrors the fallback case where the SDK should still graft onto the wrapper class.
    private final class OpaqueDelegate: NSObject, UIApplicationDelegate {}

    // MARK: - Helpers

    private let didRegisterSelector = #selector(
        UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
    )

    // MARK: - Tests

    func testResolveTargetReturnsInitialClassWhenItImplementsTheMethod() {
        let delegate = DirectAppDelegate()
        let resolved = KlaviyoAppDelegateSwizzler.testHook_resolveSwizzleTargetClass(for: delegate)
        XCTAssertTrue(resolved == DirectAppDelegate.self,
                      "Direct implementor should be the swizzle target")
    }

    func testResolveTargetWalksForwardingProxyToInnerClass() {
        // The forwarding proxy doesn't have `didRegister` in its own IMP table; its inner
        // DirectAppDelegate does. The swizzler must follow `-forwardingTargetForSelector:`
        // and resolve to DirectAppDelegate's class so the IMP exchange actually intercepts
        // the host's method.
        let inner = DirectAppDelegate()
        let proxy = ForwardingProxyDelegate(inner: inner)
        XCTAssertNil(class_getInstanceMethod(ForwardingProxyDelegate.self, didRegisterSelector),
                     "Proxy class must not have the method in its IMP table; otherwise we're not testing the forwarding path")
        XCTAssertTrue(proxy.responds(to: didRegisterSelector),
                      "Proxy must respond via forwarding for this test to be meaningful")

        let resolved = KlaviyoAppDelegateSwizzler.testHook_resolveSwizzleTargetClass(for: proxy)
        XCTAssertTrue(resolved == DirectAppDelegate.self,
                      "Forwarding proxy should resolve to inner DirectAppDelegate, got \(resolved)")
    }

    func testResolveTargetFallsBackToInitialClassWhenNoForwardingTarget() {
        // No forwarding, no IMP. We can't reach a real implementor — fall back to the
        // initial class so we can graft our IMP somewhere.
        let opaque = OpaqueDelegate()
        let resolved = KlaviyoAppDelegateSwizzler.testHook_resolveSwizzleTargetClass(for: opaque)
        XCTAssertTrue(resolved == OpaqueDelegate.self,
                      "With no forwarding target, should fall back to the initial class")
    }
}
