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

@Suite
@MainActor
struct OnceCallbackTests {
    /// The body must be called on the first invocation.
    @Test
    func callsBodyOnFirstInvocation() {
        var count = 0
        let once = OnceCallback<Void> { count += 1 }
        once()
        #expect(count == 1)
    }

    /// Subsequent calls after the first must be no-ops.
    @Test
    func ignoresSubsequentInvocations() {
        var count = 0
        let once = OnceCallback<Void> { count += 1 }
        once()
        once()
        once()
        #expect(count == 1)
    }

    /// The body receives the value passed on the first call.
    @Test
    func forwardsInputToBody() {
        var received: Int?
        let once = OnceCallback<Int> { received = $0 }
        once(42)
        once(99)
        #expect(received == 42)
    }

    /// If the callback is never invoked, the body must never fire.
    @Test
    func doesNotCallBodyWhenNeverInvoked() {
        var called = false
        _ = OnceCallback<Void> { called = true }
        #expect(called == false)
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
