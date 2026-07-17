//
// ProfileEventObserver.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Combine
import Foundation
import KlaviyoCore
import KlaviyoSwift
import OSLog

class ProfileEventObserver {
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
