//
//  MockIAFWebViewDelegate.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/12/25.
//

@testable @_spi(KlaviyoPrivate) import KlaviyoForms
import Foundation

class MockIAFWebViewDelegate: NSObject, KlaviyoWebViewDelegate {
    enum PreloadResult {
        case formWillAppear(delay: UInt64)
        case didFailNavigation(delay: UInt64)
        case none
    }

    let viewModel: IAFWebViewModel

    var preloadResult: PreloadResult?
    var preloadUrlCalled = false
    var evaluateJavaScriptCalled = false

    init(viewModel: IAFWebViewModel) {
        self.viewModel = viewModel
    }

    func preloadUrl() {
        viewModel.handleNavigationEvent(.didCommitNavigation)
        preloadUrlCalled = true

        Task {
            if let result = preloadResult {
                switch result {
                case let .formWillAppear(delay):
                    try? await Task.sleep(nanoseconds: delay)

                    let scriptMessage = MockWKScriptMessage(
                        name: "KlaviyoNativeBridge",
                        body: """
                        {
                          "type": "formWillAppear",
                          "data": {
                            "formId": "abc123"
                          }
                        }
                        """)

                    viewModel.handleScriptMessage(scriptMessage)

                case let .didFailNavigation(delay):
                    try? await Task.sleep(nanoseconds: delay)
                    viewModel.handleNavigationEvent(.didFailNavigation)

                case .none:
                    // don't do anything
                    return
                }
            }
        }
    }

    func evaluateJavaScript(_ script: String) async throws -> Any {
        evaluateJavaScriptCalled = true
        return true
    }

    func dismiss() {}
}
