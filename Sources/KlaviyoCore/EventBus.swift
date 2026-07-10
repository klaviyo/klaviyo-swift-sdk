//
//  EventBus.swift
//  klaviyo-swift-sdk
//

import Combine

/// Read-only view of the outbound event stream. Consumers (e.g. KlaviyoForms)
/// depend on this rather than the concrete bus, so the implementation can change.
public protocol EventPublishing {
    /// Replays recently buffered events (bounded) to a new subscriber, then emits live events.
    func eventPublisher() -> AnyPublisher<Event, Never>
}

/// Write access to the event stream. Intended for `KlaviyoSwift` only.
public protocol EventBroadcasting {
    func publish(_ event: Event)
}

/// Outbound event bus: KlaviyoSwift publishes enriched events; consumers observe them.
/// Mirrors the `IdentityStore` pattern. The bounded replay buffer preserves the
/// "event published before subscriber attaches" race fix (e.g. Opened Push at cold launch).
public final class EventBus: EventPublishing, EventBroadcasting {
    public static let shared = EventBus()

    private let subject = PassthroughSubject<Event, Never>()
    private let buffer: EventBuffer

    // `init` is accessible so tests exercise a fresh bus rather than mutating `shared`.
    init(buffer: EventBuffer = EventBuffer()) {
        self.buffer = buffer
    }

    public func publish(_ event: Event) {
        buffer.buffer(event)
        subject.send(event)
    }

    public func eventPublisher() -> AnyPublisher<Event, Never> {
        Deferred {
            let buffered = self.buffer.getRecentEvents()
            return self.subject
                .prepend(buffered) // guaranteed order: replay first, then live
        }
        .eraseToAnyPublisher()
    }

    /// Test-support: clears the replay buffer for isolation between tests and for the
    /// Core reset surface. Subscribers are held by consumers, not the bus,
    /// so a reset only clears the bounded replay buffer.
    public func reset() {
        buffer.clear()
    }
}
