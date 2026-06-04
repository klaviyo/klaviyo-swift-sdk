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
        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {}
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
            inner.responds(to: aSelector) ? inner : super.forwardingTarget(for: aSelector)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || inner.responds(to: aSelector)
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

    func testResolveTargetDirectImplementor() {
        let delegate = DirectAppDelegate()
        let resolved = KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: delegate)
        XCTAssertTrue(resolved == DirectAppDelegate.self)
    }

    func testResolveTargetForwardingProxy() {
        // The proxy has no `didRegister` IMP of its own; its inner DirectAppDelegate does.
        // The resolver must follow `-forwardingTargetForSelector:` and return the inner class
        // so the IMP exchange intercepts the real implementor rather than the wrapper.
        let inner = DirectAppDelegate()
        let proxy = ForwardingProxyDelegate(inner: inner)

        XCTAssertNil(
            class_getInstanceMethod(ForwardingProxyDelegate.self, didRegisterSelector),
            "Proxy class must not have the method in its IMP table; otherwise we're not testing the forwarding path"
        )
        XCTAssertTrue(
            proxy.responds(to: didRegisterSelector),
            "Proxy must respond via forwarding for this test to be meaningful"
        )

        let resolved = KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: proxy)
        XCTAssertTrue(resolved == DirectAppDelegate.self)
    }

    func testResolveTargetOpaqueDelegate() {
        // No forwarding, no IMP — resolver falls back to the initial class so the swizzler
        // can still graft our IMP somewhere and the SDK receives the token.
        let opaque = OpaqueDelegate()
        let resolved = KlaviyoAppDelegateSwizzler.resolveSwizzleTargetClass(for: opaque)
        XCTAssertTrue(resolved == OpaqueDelegate.self)
    }
}
