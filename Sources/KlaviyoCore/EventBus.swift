//
//  EventBus.swift
//  klaviyo-swift-sdk
//

import Combine
import Foundation

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

    package struct Origin {
        fileprivate let generation: UInt64
        fileprivate let arrivedAt: TimeInterval
    }

    package struct Delivery {
        package let event: Event
        fileprivate let generation: UInt64
    }

    private let lock = NSRecursiveLock()
    private let buffer: EventBuffer
    private var generation: UInt64 = 0
    private var context: (apiKey: String?, identity: ProfileData)?
    private var subscribers: [UUID: EventSubscription] = [:]

    // `init` is accessible so tests exercise a fresh bus rather than mutating `shared`.
    init(buffer: EventBuffer = EventBuffer()) {
        self.buffer = buffer
    }

    public func publish(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        publish(event, origin: Origin(generation: generation, arrivedAt: buffer.currentTime))
    }

    package func updateContext(apiKey: String?, identity: ProfileData) {
        lock.lock()
        defer { lock.unlock() }
        if let previous = context {
            let wasAnonymous = [
                previous.identity.email,
                previous.identity.phoneNumber,
                previous.identity.externalId
            ]
            .allSatisfy { $0?.isEmpty != false }
            let anonymousContinuity = wasAnonymous && previous.identity.anonymousId != nil &&
                previous.identity.anonymousId == identity.anonymousId
            if previous.apiKey != apiKey ||
                (!anonymousContinuity && IdentityTransition.classify(
                    previous: previous.identity,
                    next: identity
                ) == .replacement) {
                generation &+= 1
                buffer.clear()
            }
        }
        context = (apiKey, identity)
    }

    package func captureOrigin(apiKey: String?, identity: ProfileData) -> Origin {
        lock.lock()
        defer { lock.unlock() }
        updateContext(apiKey: apiKey, identity: identity)
        return Origin(generation: generation, arrivedAt: buffer.currentTime)
    }

    package func publish(_ event: Event, origin: Origin) {
        lock.lock()
        defer { lock.unlock() }
        guard origin.generation == generation else { return }
        buffer.buffer(event, arrivedAt: origin.arrivedAt)
        let delivery = Delivery(event: event, generation: generation)
        let currentSubscribers = Array(subscribers.values)
        currentSubscribers.forEach { $0.enqueue(delivery) }
        currentSubscribers.forEach { $0.drain() }
    }

    package func isCurrent(_ delivery: Delivery) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return delivery.generation == generation
    }

    public func eventPublisher() -> AnyPublisher<Event, Never> {
        formEventPublisher(replayWindow: 10).map(\.event).eraseToAnyPublisher()
    }

    package func formEventPublisher(replayWindow: TimeInterval) -> AnyPublisher<Delivery, Never> {
        ReplayPublisher(eventBus: self, replayWindow: replayWindow).eraseToAnyPublisher()
    }

    /// Clears replay history and invalidates events queued for the previous context.
    package func reset() {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        context = nil
        buffer.clear()
    }

    private struct ReplayPublisher: Publisher {
        // swiftlint:disable:next nesting
        typealias Output = Delivery
        // swiftlint:disable:next nesting
        typealias Failure = Never
        let eventBus: EventBus
        let replayWindow: TimeInterval

        func receive<S: Subscriber>(subscriber: S) where S.Input == Delivery, S.Failure == Never {
            eventBus.lock.lock()
            defer { eventBus.lock.unlock() }
            let subscription = EventSubscription(eventBus: eventBus, downstream: AnySubscriber(subscriber))
            let window = replayWindow.isNaN ? 10 : Swift.min(30, Swift.max(0, replayWindow))
            for event in eventBus.buffer.getRecentEvents(maxAge: window) {
                subscription.enqueue(Delivery(event: event, generation: eventBus.generation))
            }
            eventBus.subscribers[subscription.id] = subscription
            subscriber.receive(subscription: subscription)
            subscription.drain()
        }
    }

    private final class EventSubscription: Subscription {
        let id = UUID()
        private weak var eventBus: EventBus?
        private var downstream: AnySubscriber<Delivery, Never>?
        private var pending: [Delivery] = []
        private var demand: Subscribers.Demand = .none
        private var draining = false

        init(eventBus: EventBus, downstream: AnySubscriber<Delivery, Never>) {
            self.eventBus = eventBus
            self.downstream = downstream
        }

        func request(_ demand: Subscribers.Demand) {
            guard let eventBus else { return }
            eventBus.lock.lock()
            defer { eventBus.lock.unlock() }
            self.demand += demand
            drain()
        }

        func cancel() {
            guard let eventBus else { return }
            eventBus.lock.lock()
            defer { eventBus.lock.unlock() }
            eventBus.subscribers[id] = nil
            downstream = nil
            pending.removeAll()
        }

        func enqueue(_ delivery: Delivery) {
            guard downstream != nil else { return }
            if !draining, demand == .none, pending.count >= 10 { return }
            pending.append(Delivery(event: EventBuffer.copy(delivery.event), generation: delivery.generation))
        }

        func drain() {
            guard !draining, let eventBus else { return }
            draining = true
            defer { draining = false }
            while demand > .none, !pending.isEmpty, let downstream {
                let delivery = pending.removeFirst()
                guard eventBus.isCurrent(delivery) else { continue }
                demand -= 1
                demand += downstream.receive(delivery)
            }
        }
    }
}
