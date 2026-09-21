//
//  KlaviyoEventDispatcher.swift
//  klaviyo-swift-sdk
//

import KlaviyoCore

/// KlaviyoSwift's implementation of the Core `EventDispatching` contract.
/// Routes inbound commands to the direct `KlaviyoOrchestration` functions.
struct KlaviyoEventDispatcher: EventDispatching {
    func dispatch(_ command: InboundCommand) {
        switch command {
        case let .createEvent(event):
            dispatchOnMainThread { KlaviyoOrchestration.enqueueEvent(event) }
        case let .aggregateEvent(payload):
            dispatchOnMainThread { KlaviyoOrchestration.enqueueAggregateEvent(payload) }
        case let .deepLink(deepLinkURL):
            Task { @MainActor in await DeepLinkManager.openDeepLink(deepLinkURL) }
        }
    }
}
