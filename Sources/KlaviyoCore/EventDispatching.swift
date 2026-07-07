//
//  EventDispatching.swift
//  klaviyo-swift-sdk
//

import Foundation

/// Closed vocabulary of inbound commands other modules hand to the SDK's analytics engine.
public enum InboundCommand {
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

    private let lock = NSLock()
    private var target: EventDispatching?

    /// Register the dispatch implementation (idempotent — replaces any prior target).
    public func register(_ target: EventDispatching) {
        lock.lock()
        self.target = target
        lock.unlock()
    }

    /// Forward a command to the registered target. If none is registered, emit a loud
    /// developer warning rather than silently dropping (buffering deferred to MAGE-833).
    public func dispatch(_ command: InboundCommand) {
        lock.lock()
        let currentTarget = target
        lock.unlock() // release before forwarding — a downstream effect may re-enter dispatch
        if let currentTarget {
            currentTarget.dispatch(command)
        } else {
            environment.emitDeveloperWarning("EventDispatcher: dispatch before registration")
        }
    }
}
