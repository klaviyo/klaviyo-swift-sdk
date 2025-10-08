//
//  ProfileEventObserver.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/22/25.
//

import Combine
import Foundation
import KlaviyoCore
import KlaviyoSwift
import OSLog

class ProfileEventObserver: JSBridgeObserver {
    private var cancellable: AnyCancellable?
    private var eventsContinuation: AsyncStream<Event>.Continuation?
    private let stream: AsyncStream<Event>

    var eventsStream: AsyncStream<Event> { stream }

    init() {
        (stream, eventsContinuation) = AsyncStream.makeStream(of: Event.self)
    }

    func startObserving() {
        guard cancellable == nil else { return }
        cancellable = KlaviyoInternal.eventPublisher()
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
