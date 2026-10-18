//
//  ProfileEventObserver.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/22/25.
//

import Combine
import Foundation
import KlaviyoCore
import OSLog

class ProfileEventObserver {
    private var cancellable: AnyCancellable?
    private var eventsContinuation: AsyncStream<EventBus.Delivery>.Continuation?
    private let stream: AsyncStream<EventBus.Delivery>

    var eventsStream: AsyncStream<EventBus.Delivery> {
        stream
    }

    init() {
        (stream, eventsContinuation) = AsyncStream.makeStream(of: EventBus.Delivery.self)
    }

    func startObserving(replayWindow: TimeInterval = 10) {
        guard cancellable == nil else { return }
        cancellable = EventBus.shared.formEventPublisher(replayWindow: replayWindow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                eventsContinuation?.yield(event)
            }
    }

    func stopObserving() {
        cancellable?.cancel()
        cancellable = nil
        eventsContinuation?.finish()
        eventsContinuation = nil
    }

    deinit {
        stopObserving()
    }
}
