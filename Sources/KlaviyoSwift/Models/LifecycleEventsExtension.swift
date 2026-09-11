//
//  LifecycleEventsExtension.swift
//
//
//  Created by Ajay Subramanya on 8/13/24.
//

import Combine
import Foundation
import KlaviyoCore

extension LifeCycleEvents {
    var transformToKlaviyoAction: KlaviyoAction {
        switch self {
        case .terminated:
            return .stop
        case .foregrounded:
            return .start
        case .backgrounded:
            return .stop
        case let .reachabilityChanged(status):
            return .networkConnectivityChanged(status)
        }
    }
}

extension Publisher where Output == LifeCycleEvents, Failure == Never {
    /// Bridges the lifecycle publisher to an `AsyncStream` for consumption by the long-lived
    /// `completeInitialization` effect. `AnyPublisher.values` requires iOS 15; this `sink`-based
    /// bridge works back to the package's iOS 13 floor and forwards completion so a finite publisher
    /// (e.g. the test lifecycle stream) terminates the `for await` loop.
    func lifecycleEventStream() -> AsyncStream<LifeCycleEvents> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let cancellable = sink(
                receiveCompletion: { _ in continuation.finish() },
                receiveValue: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
