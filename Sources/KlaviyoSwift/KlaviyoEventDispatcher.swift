//
//  KlaviyoEventDispatcher.swift
//  klaviyo-swift-sdk
//

import KlaviyoCore

/// KlaviyoSwift's TCA-backed implementation of the Core `EventDispatching` contract.
/// Routes inbound commands to the analytics reducer.
struct KlaviyoEventDispatcher: EventDispatching {
    func dispatch(_ command: InboundCommand) {
        switch command {
        case let .aggregateEvent(payload):
            dispatchOnMainThread(action: .enqueueAggregateEvent(payload))
        case let .deepLink(deepLinkURL):
            dispatchOnMainThread(action: .openDeepLink(deepLinkURL))
        }
    }
}
