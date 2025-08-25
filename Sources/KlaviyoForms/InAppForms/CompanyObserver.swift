//
//  CompanyObserver.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/25.
//

import Combine
import Foundation
import KlaviyoCore
import KlaviyoSwift
import OSLog

class CompanyObserver: JSBridgeObserver {
    var apiKeyCancellable: AnyCancellable?
    private var initializationWarningTask: Task<Void, Never>?

    private let manager: IAFPresentationManager
    private let configuration: InAppFormsConfig

    init(manager: IAFPresentationManager, configuration: InAppFormsConfig) {
        self.manager = manager
        self.configuration = configuration
    }

    func startObserving() {
        apiKeyCancellable = KlaviyoInternal.apiKeyPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }

                switch result {
                case let .success(apiKey):
                    if #available(iOS 14.0, *) {
                        Logger.webViewLogger.info("Received API key change. New API key: \(apiKey)")
                    }

                    initializationWarningTask?.cancel()
                    initializationWarningTask = nil
                    Task { [weak self] in
                        guard let self else { return }
                        await self.manager.reinitializeIAFForNewAPIKey(apiKey, configuration: self.configuration)
                    }
                case let .failure(sdkError):
                    handleAPIKeyError(sdkError)
                }
            }
    }

    func stopObserving() {
        apiKeyCancellable?.cancel()
        apiKeyCancellable = nil
    }

    private func handleAPIKeyError(_ sdkError: SDKError) {
        switch sdkError {
        case .notInitialized:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("SDK is not initialized. Skipping form initialization until the SDK is successfully initialized.")
            }
        case .apiKeyNilOrEmpty:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("SDK API key is empty or nil. Skipping form initialization until a valid API key is received.")
            }
        }

        initializationWarningTask = Task {
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds in nanoseconds
                // Check if task was cancelled before emitting warning
                try Task.checkCancellation()
                environment.emitDeveloperWarning("SDK must be initialized before usage.")
            } catch {
                // Task was cancelled or other error occurred
                return
            }
        }
    }
}
