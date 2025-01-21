//
//  KlaviyoWebViewModel.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/30/24.
//

import Combine
import Foundation
import WebKit

@_spi(KlaviyoPrivate)
public protocol KlaviyoWebViewDelegate: AnyObject {
    @MainActor
    func preloadUrl()

    @MainActor
    func evaluateJavaScript(_ script: String) async throws -> Any
}

@_spi(KlaviyoPrivate)
public class KlaviyoWebViewModel: KlaviyoWebViewModeling {
    public let url: URL
    public let loadScripts: [String: WKUserScript]?
    public weak var delegate: KlaviyoWebViewDelegate?

    private let (navEventStream, navEventContinuation) = AsyncStream.makeStream(of: WKNavigationEvent.self)

    public init(url: URL) {
        self.url = url
        loadScripts = KlaviyoWebViewModel.initializeLoadScripts()
    }

    private static func initializeLoadScripts() -> [String: WKUserScript] {
        var scripts: [String: WKUserScript] = [:]

        if let closeHandlerScript = try? ResourceLoader.getResourceContents(path: "closeHandler", type: "js") {
            let script = WKUserScript(source: closeHandlerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            scripts["closeHandler"] = script
        }

        return scripts
    }

    /// Tells the delegate's ``WKWebView`` to preload the URL provided in this ViewModel.
    ///
    /// This async method will return after the preload has completed.
    ///
    /// By preloading, we can load the URL "headless", so that the ViewController containing
    /// the ``WKWebView`` will only be presented after the site has successfully loaded.
    ///
    /// The caller of this method should `await` completion of this method, then present the ViewController.
    /// - Parameter timeout: the amount of time, in milliseconds, to wait before throwing a `timeout` error.
    public func preloadWebsite(timeout: UInt64) async throws {
        guard let delegate else { return }

        await delegate.preloadUrl()

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: timeout)
                    throw PreloadError.timeout
                }

                // Add the navigation event task to the group
                group.addTask { [weak self] in
                    guard let self else { return }
                    for await event in self.navEventStream {
                        switch event {
                        case .didFinishNavigation:
                            return
                        case .didFailNavigation:
                            throw PreloadError.navigationFailed
                        case .didCommitNavigation,
                             .didStartProvisionalNavigation,
                             .didFailProvisionalNavigation,
                             .didReceiveServerRedirectForProvisionalNavigation:
                            continue
                        }
                    }
                }

                if let _ = try await group.next() {
                    // when the navigation task returns, we want to
                    // cancel both the timeout task and the navigation task
                    group.cancelAll()
                }
            }
        } catch let error as PreloadError {
            switch error {
            case .timeout:
                print("Operation timed out: \(error)")
                throw error
            case .navigationFailed:
                print("Navigation failed: \(error)")
                throw error
            }
        } catch {
            print("Operation encountered an error: \(error)")
            throw error
        }
    }

    // MARK: handle WKWebView events

    public func handleNavigationEvent(_ event: WKNavigationEvent) {
        navEventContinuation.yield(event)
    }

    public func handleScriptMessage(_ message: WKScriptMessage) {
        if message.name == "closeHandler" {
            // TODO: handle close button tap
            print("user tapped close button")
        }
    }
}
