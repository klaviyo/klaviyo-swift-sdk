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

    private let manager: IAFPresentationManager
    private let configuration: InAppFormsConfig

    init(manager: IAFPresentationManager, configuration: InAppFormsConfig) {
        self.manager = manager
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
                        try await self.manager.handleLifecycleEvent("foreground")
                        if self.isSessionExpired {
                            if #available(iOS 14.0, *) {
                                Logger.webViewLogger.info("App session has exceeded timeout duration; re-initializing IAF")
                            }
                            try await self.manager.reinitializeInAppForms()
                        } else {
                            try await self.manager.handleInSessionForegroundEvent()
                        }
                    case .backgrounded:
                        print("BACKGROUNDED GOT")
                        self.lastBackgrounded = Date()
                        try await self.manager.handleLifecycleEvent("background")
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

    private var isSessionExpired: Bool {
        guard let lastBackgrounded else { return false }
        let timeElapsed = Date().timeIntervalSince(lastBackgrounded)
        let timeoutDuration = configuration.sessionTimeoutDuration
        return timeElapsed > timeoutDuration
    }
}
