//
//  KlaviyoWebViewModeling.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/1/24.
//

import Combine
import Foundation
import OSLog
import WebKit

@_spi(KlaviyoPrivate)
public protocol KlaviyoWebViewModeling: AnyObject {
    var url: URL { get }
    var delegate: KlaviyoWebViewDelegate? { get set }

    /// Scripts & message handlers to be injected into the ``WKWebView`` when the website loads.
    var loadScripts: Set<WKUserScript>? { get }
    var messageHandlers: Set<String>? { get }

    var navEventStream: AsyncStream<WKNavigationEvent> { get }
    var navEventContinuation: AsyncStream<WKNavigationEvent>.Continuation { get }

    func preloadWebsite(timeout: UInt64) async throws
    func handleNavigationEvent(_ event: WKNavigationEvent)
    func handleScriptMessage(_ message: WKScriptMessage)
}

// MARK: - Default implementation

extension KlaviyoWebViewModeling {
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
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Operation timed out: \(error)")
                }
                throw error
            case .navigationFailed:
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Navigation failed: \(error)")
                }
                throw error
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Operation encountered an error: \(error)")
            }
            throw error
        }
    }

    public func handleNavigationEvent(_ event: WKNavigationEvent) {
        navEventContinuation.yield(event)
    }
}
