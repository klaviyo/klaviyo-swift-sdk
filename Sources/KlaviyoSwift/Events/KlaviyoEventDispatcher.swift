//
//  KlaviyoEventDispatcher.swift
//  klaviyo-swift-sdk
//

import KlaviyoCore

/// KlaviyoSwift's implementation of the Core `EventDispatching` contract.
/// Routes inbound commands to the direct `KlaviyoCommands` functions.
struct KlaviyoEventDispatcher: EventDispatching {
    func dispatch(_ command: InboundCommand) {
        switch command {
        case let .createEvent(event):
            dispatchOnMainThread { KlaviyoCommands.enqueueEvent(event) }
        case let .aggregateEvent(payload):
            dispatchOnMainThread { KlaviyoCommands.enqueueAggregateEvent(payload) }
        case let .deepLink(deepLinkURL):
            Task { @MainActor in await DeepLinkManager.openDeepLink(deepLinkURL) }
        }
    }
}
