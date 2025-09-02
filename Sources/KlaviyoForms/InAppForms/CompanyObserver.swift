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
    enum Event { case apiKeyUpdated(String), error(SDKError) }

    private var cancellable: AnyCancellable?
    private var initializationWarningTask: Task<Void, Never>?

    private let eventsContinuation: AsyncStream<Event>.Continuation
    let events: AsyncStream<Event>

    init() {
        var continuation: AsyncStream<Event>.Continuation!
        events = AsyncStream<Event> { continuation = $0 }
        eventsContinuation = continuation
    }

    func startObserving() {
        cancellable = KlaviyoInternal.apiKeyPublisher()
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] result in
                guard let self else { return }
                switch result {
                case let .success(key):
                    initializationWarningTask?.cancel()
                    eventsContinuation.yield(.apiKeyUpdated(key))
                case let .failure(error):
                    handleAPIKeyError(error)
                    eventsContinuation.yield(.error(error))
                }
            }
    }

    func stopObserving() {
        cancellable?.cancel()
        cancellable = nil
        initializationWarningTask?.cancel()
        initializationWarningTask = nil
        eventsContinuation.finish()
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
