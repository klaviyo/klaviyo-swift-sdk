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
    private var configuration: InAppFormsConfig
    private var lastBackgrounded: Date?

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
//                        try await self.handleLifecycleEvent("foreground")
                        if let lastBackgrounded = self.lastBackgrounded {
                            let timeElapsed = Date().timeIntervalSince(lastBackgrounded)
                            let timeoutDuration = self.configuration.sessionTimeoutDuration
                            if timeElapsed > timeoutDuration {
                                if #available(iOS 14.0, *) {
                                    Logger.webViewLogger.info("App session has exceeded timeout duration; re-initializing IAF")
                                }
                            }
                        } else {
                            // When opening Notification/Control Center, the system will not dispatch a `backgrounded` event,
                            // but it will dispatch a `foregrounded` event when Notification/Control Center is dismissed.
                            // This check ensures that don't reinitialize in this situation.
//                            if self.viewController == nil {
//                                // fresh launch
//                                try await self.initializeFormWithAPIKey()
//                            }
                        }
                    case .backgrounded:
                        self.lastBackgrounded = Date()
//                        try await self.handleLifecycleEvent("background")
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
