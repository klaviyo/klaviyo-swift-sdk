//
//  MockIAFWebViewDelegate.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/12/25.
//

@testable import KlaviyoForms
import Foundation
import UIKit

@MainActor
class MockIAFWebViewDelegate: UIViewController, KlaviyoWebViewDelegate {
    enum HandshakeResult {
        case handshakeEstablished(delay: TimeInterval)
        case none
    }

    let viewModel: IAFWebViewModel

    var handshakeResult: HandshakeResult?

    /// Records every script passed to ``evaluateJavaScript(_:)``, in call order,
    /// so tests can assert both that an update fired and what it contained.
    var evaluatedScripts: [String] = []
    var evaluateJavaScriptCalled: Bool {
        !evaluatedScripts.isEmpty
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
        evaluatedScripts.append(script)
        return true
    }

    func dismiss() {}
}
