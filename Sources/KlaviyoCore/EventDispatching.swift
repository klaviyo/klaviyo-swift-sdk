//
//  EventDispatching.swift
//  klaviyo-swift-sdk
//

import Foundation

/// Closed vocabulary of inbound commands other modules hand to the SDK's analytics engine.
public enum InboundCommand {
    case createEvent(Event)
    case aggregateEvent(AggregateEventPayload)
    case deepLink(URL)
}

/// Inbound dispatch into the SDK's analytics engine. Implemented by `KlaviyoSwift`.
public protocol EventDispatching {
    func dispatch(_ command: InboundCommand)
}

/// Registration slot + forwarder for inbound dispatch. `KlaviyoSwift` registers its
/// implementation at `KlaviyoSDK.init`; callers (e.g. `KlaviyoForms`) dispatch through `shared`.
public final class EventDispatcher {
    public static let shared = EventDispatcher()

    private let lock = UnfairLock()
    private var target: EventDispatching?

    /// Register the dispatch implementation (idempotent — replaces any prior target).
    public func register(_ target: EventDispatching) {
        lock.withLock { self.target = target }
    }

    /// Forward a command to the registered target. If none is registered, emit a loud
    /// developer warning rather than silently dropping (buffering is deferred follow-up work).
    public func dispatch(_ command: InboundCommand) {
        // Snapshot under the lock, then forward OUTSIDE it — a downstream effect may re-enter
        // dispatch, and the lock is non-recursive.
        let currentTarget = lock.withLock { target }
        if let currentTarget {
            currentTarget.dispatch(command)
        } else {
            environment.emitDeveloperWarning("EventDispatcher: dispatch before registration")
        }
    }

    /// Unregister the current target (test-support / Core reset surface).
    package func reset() {
        lock.withLock { target = nil }
    }
}
