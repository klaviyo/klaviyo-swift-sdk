//
//  LifecycleObserver.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/25.
//

import Combine
import Foundation
import KlaviyoCore
import KlaviyoSwift
import OSLog

class LifecycleObserver: JSBridgeObserver {
    private var lifecycleCancellable: AnyCancellable?
    private var lastBackgrounded: Date?

    private var configuration: InAppFormsConfig

    init(configuration: InAppFormsConfig) {
        self.configuration = configuration
    }

    func startObserving() {
        lifecycleCancellable = environment.appLifeCycle.lifeCycleEvents()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    switch event {
                    case .terminated:
                        break
                    case .foregrounded:
                        try await IAFPresentationManager.shared.handleLifecycleEvent("foreground")
                        if let lastBackgrounded = self.lastBackgrounded {
                            let timeElapsed = Date().timeIntervalSince(lastBackgrounded)
                            let timeoutDuration = self.configuration.sessionTimeoutDuration
                            if timeElapsed > timeoutDuration {
                                if #available(iOS 14.0, *) {
                                    Logger.webViewLogger.info("App session has exceeded timeout duration; re-initializing IAF")
                                }
                                try await IAFPresentationManager.shared.reinitializeInAppForms()
                            }
                        } else {
                            try await IAFPresentationManager.shared.initializeForForegroundEvent()
                        }
                    case .backgrounded:
                        self.lastBackgrounded = Date()
                        try await IAFPresentationManager.shared.handleLifecycleEvent("background")
                    case .reachabilityChanged:
                        break
                    }
                }
            }
    }

    func stopObserving() {
        lifecycleCancellable?.cancel()
        lifecycleCancellable = nil
        lastBackgrounded = nil
    }
}
