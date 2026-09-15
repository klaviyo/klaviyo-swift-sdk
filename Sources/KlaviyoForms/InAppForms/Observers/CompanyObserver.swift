//
//  CompanyObserver.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/25.
//

import Combine
import Foundation
import KlaviyoCore
import OSLog

class CompanyObserver {
    enum Event {
        case apiKeyUpdated(String), error(SDKError)
    }

    private var cancellable: AnyCancellable?
    private var initializationWarningTask: Task<Void, Never>?

    private var eventsContinuation: AsyncStream<Event>.Continuation?
    private let stream: AsyncStream<Event>

    var eventsStream: AsyncStream<Event> { stream }

    init() {
        (stream, eventsContinuation) = AsyncStream.makeStream(of: Event.self)
    }

    func startObserving() {
        guard cancellable == nil else { return }
        cancellable = SDKConfigStore.shared.publisher
            .map(\.apiKey)
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] apiKey in
                guard let self else { return }
                if let apiKey, !apiKey.isEmpty {
                    if #available(iOS 14.0, *) {
                        Logger.webViewLogger.info("Received API key change. New API key: \(apiKey)")
                    }
                    initializationWarningTask?.cancel()
                    eventsContinuation?.yield(.apiKeyUpdated(apiKey))
                } else {
                    // `SDKConfigStore` carries only the value, not the SDK's init state, so a
                    // missing/empty key can't be distinguished from "not initialized"; treat both
                    // as not-initialized (the case this observer exists to guard against).
                    handleAPIKeyError(.notInitialized)
                    eventsContinuation?.yield(.error(.notInitialized))
                }
            }
    }

    func stopObserving() {
        initializationWarningTask?.cancel()
        initializationWarningTask = nil
        cancellable?.cancel()
        cancellable = nil
        eventsContinuation?.finish()
        eventsContinuation = nil
    }

    deinit {
        stopObserving()
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
