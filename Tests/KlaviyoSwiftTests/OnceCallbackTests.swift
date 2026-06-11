//
//  OnceCallbackTests.swift
//  KlaviyoSwiftTests
//
//  Created by Glenn Brannelly on 5/29/26.
//

@testable import KlaviyoSwift
import Foundation

#if canImport(Testing)
import Testing

// Captures mutable state in @Sendable closures without data races.
// Safe here because the suite is @MainActor and OnceCallback dispatches to the main thread.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

@Suite
@MainActor
struct OnceCallbackTests {
    /// The body must be called on the first invocation.
    @Test
    func callsBodyOnFirstInvocation() {
        let count = Box(0)
        let once = OnceCallback<Void> { count.value += 1 }
        once()
        #expect(count.value == 1)
    }

    /// Subsequent calls after the first must be no-ops.
    @Test
    func ignoresSubsequentInvocations() {
        let count = Box(0)
        let once = OnceCallback<Void> { count.value += 1 }
        once()
        once()
        once()
        #expect(count.value == 1)
    }

    /// The body receives the value passed on the first call.
    @Test
    func forwardsInputToBody() {
        let received = Box<Int?>(nil)
        let once = OnceCallback<Int> { received.value = $0 }
        once(42)
        once(99)
        #expect(received.value == 42)
    }

    /// If the callback is never invoked, the body must never fire.
    @Test
    func doesNotCallBodyWhenNeverInvoked() {
        let called = Box(false)
        _ = OnceCallback<Void> { called.value = true }
        #expect(called.value == false)
    }

    /// When invoked off the main thread the body must still run on the main thread.
    @Test
    func callsBodyOnMainThreadWhenInvokedOffMain() async {
        let isMain: Bool = await withCheckedContinuation { continuation in
            let once = OnceCallback<Void> { continuation.resume(returning: Thread.isMainThread) }
            Task.detached { once() }
        }
        #expect(isMain)
    }
}
#endif
