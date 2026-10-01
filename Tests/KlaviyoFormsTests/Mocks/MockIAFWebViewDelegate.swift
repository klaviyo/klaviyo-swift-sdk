//
//  MockIAFWebViewDelegate.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/12/25.
//

@testable import KlaviyoForms
import Foundation
import UIKit
import XCTest

@MainActor
class MockIAFWebViewDelegate: UIViewController, KlaviyoWebViewDelegate {
    enum HandshakeResult {
        case handshakeEstablished(delay: TimeInterval)
        case none
    }

    let viewModel: IAFWebViewModel

    var handshakeResult: HandshakeResult?

    /// Records every script passed to ``evaluateJavaScript(_:)``, in completion order,
    /// so tests can assert both that an update fired and what it contained.
    var evaluatedScripts: [String] = []
    var evaluateJavaScriptCalled: Bool {
        !evaluatedScripts.isEmpty
    }

    /// The `data-klaviyo-jwt` updates among ``evaluatedScripts``, in call order.
    var authTokenScripts: [String] {
        evaluatedScripts.filter { $0.contains("data-klaviyo-jwt") }
    }

    private var scriptWaiters: [(text: String, expectation: XCTestExpectation)] = []
    /// A script evaluation parked by ``holdScript(containing:)``.
    struct ScriptHold {
        /// Opens once the held evaluation has started.
        let reached = Latch()
        /// Lets the held evaluation complete once opened.
        let release = Latch()
    }

    private var scriptHolds: [(text: String, hold: ScriptHold)] = []
    private var scriptFailures: [String] = []

    /// Makes the next evaluation of a script containing `text` throw instead of completing.
    /// A failed evaluation is not recorded in ``evaluatedScripts``.
    func failScript(containing text: String) {
        scriptFailures.append(text)
    }

    /// Makes the next evaluation of a script containing `text` wait for the returned hold's
    /// ``ScriptHold/release`` before it completes and is recorded in ``evaluatedScripts``.
    func holdScript(containing text: String) -> ScriptHold {
        let hold = ScriptHold()
        scriptHolds.append((text, hold))
        return hold
    }

    /// Suspends until a script containing `text` has been evaluated, resuming as soon as
    /// it is. Fails the current test if none arrives within `timeout` seconds.
    func waitForScript(
        containing text: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        guard !evaluatedScripts.contains(where: { $0.contains(text) }) else { return }
        let expectation = XCTestExpectation(description: "script containing \(text)")
        scriptWaiters.append((text, expectation))
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: timeout)
        if result != .completed {
            XCTFail("Timed out waiting for a script containing \(text)", file: file, line: line)
        }
    }

    init(viewModel: IAFWebViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func preloadUrl() {
        viewModel.handleNavigationEvent(.didCommitNavigation)

        Task {
            if let result = handshakeResult {
                switch result {
                case let .handshakeEstablished(delay):
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                    let scriptMessage = MockWKScriptMessage(
                        name: "KlaviyoNativeBridge",
                        body: """
                        {"type":"handShook","data":{}}
                        """
                    )

                    viewModel.handleScriptMessage(scriptMessage)

                case .none:
                    // don't do anything
                    return
                }
            }
        }
    }

    func evaluateJavaScript(_ script: String) async throws -> Any? {
        if let index = scriptHolds.firstIndex(where: { script.contains($0.text) }) {
            let hold = scriptHolds.remove(at: index).hold
            await hold.reached.open()
            await hold.release.wait()
        }
        if let index = scriptFailures.firstIndex(where: { script.contains($0) }) {
            scriptFailures.remove(at: index)
            throw ScriptEvaluationFailure()
        }
        evaluatedScripts.append(script)
        scriptWaiters.removeAll { waiter in
            guard script.contains(waiter.text) else { return false }
            waiter.expectation.fulfill()
            return true
        }
        return true
    }

    func dismiss() {}
}

/// Thrown by ``MockIAFWebViewDelegate/evaluateJavaScript(_:)`` for a script registered with
/// ``MockIAFWebViewDelegate/failScript(containing:)``.
struct ScriptEvaluationFailure: Error {}

extension MockIAFWebViewDelegate {
    /// Upper bound for ``awaitScript(containing:file:line:)``, which only exists to fail a test
    /// whose script never arrives.
    static let scriptSafeguard: TimeInterval = 60

    /// Suspends until a script containing `text` has been evaluated, resuming as soon as it is.
    func awaitScript(
        containing text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await waitForScript(containing: text, timeout: Self.scriptSafeguard, file: file, line: line)
    }
}
