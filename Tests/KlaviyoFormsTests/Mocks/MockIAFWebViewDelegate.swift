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
    enum EvaluationError: Error {
        case documentNotReady
    }

    enum HandshakeResult {
        case handshakeEstablished(delay: TimeInterval)
        case none
    }

    let viewModel: IAFWebViewModel

    var handshakeResult: HandshakeResult?

    /// Records every script passed to ``evaluateJavaScript(_:)``, in call order,
    /// so tests can assert both that an update fired and what it contained.
    var evaluatedScripts: [String] = []
    var onEvaluateJavaScript: ((String) -> Void)?
    var onEvaluateJavaScriptAsync: ((String) async throws -> Void)?
    private(set) var documentAuthToken: String?
    private var isDocumentReady = false
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

    func startNavigation() {
        viewModel.handleNavigationEvent(.didStartProvisionalNavigation)
    }

    func commitNavigation() {
        documentAuthToken = nil
        isDocumentReady = false
        viewModel.handleNavigationEvent(.didCommitNavigation)
    }

    func finishNavigation() {
        viewModel.loadScripts?.forEach { applyAuthScript($0.source) }
        isDocumentReady = true
        viewModel.handleNavigationEvent(.didFinishNavigation)
    }

    func failProvisionalNavigation() {
        viewModel.handleNavigationEvent(.didFailProvisionalNavigation)
    }

    func evaluateJavaScript(_ script: String) async throws -> Any? {
        evaluatedScripts.append(script)
        guard isDocumentReady else { throw EvaluationError.documentNotReady }
        try await onEvaluateJavaScriptAsync?(script)
        applyAuthScript(script)
        onEvaluateJavaScript?(script)
        return true
    }

    private func applyAuthScript(_ script: String) {
        let prefix = "document.head.setAttribute('data-klaviyo-jwt', '"
        let suffix = "');"
        if script.hasPrefix(prefix), script.hasSuffix(suffix) {
            documentAuthToken = String(script.dropFirst(prefix.count).dropLast(suffix.count))
        } else if script == "document.head.removeAttribute('data-klaviyo-jwt');" {
            documentAuthToken = nil
        }
    }

    func dismiss() {}
}
