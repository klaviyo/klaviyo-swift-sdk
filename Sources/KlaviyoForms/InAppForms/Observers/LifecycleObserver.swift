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
    enum Event {
        case foregrounded
        case backgrounded
    }

    private var cancellable: AnyCancellable?
    private var eventsContinuation: AsyncStream<Event>.Continuation?
    var eventsStream: AsyncStream<Event>?

    init() {}

    func startObserving() {
        // Only create a new stream if one doesn't exist
        if eventsStream == nil {
            let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
            eventsStream = stream
            eventsContinuation = continuation
        }

        cancellable = environment.appLifeCycle.lifeCycleEvents()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch event {
                    case .foregrounded:
                        eventsContinuation?.yield(.foregrounded)
                    case .backgrounded:
                        eventsContinuation?.yield(.backgrounded)
                    default:
                        break
                    }
                }
            }
    }

    func stopObserving() {
        cancellable?.cancel()
        cancellable = nil
        eventsContinuation?.finish()
        eventsContinuation = nil
        eventsStream = nil
    }
}
