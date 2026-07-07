//
//  KlaviyoEventDispatcher.swift
//  klaviyo-swift-sdk
//

import KlaviyoCore

/// KlaviyoSwift's TCA-backed implementation of the Core `EventDispatching` contract.
/// Routes inbound commands to the existing `KlaviyoInternal` dispatch methods.
struct KlaviyoEventDispatcher: EventDispatching {
    func dispatch(_ command: InboundCommand) {
        switch command {
        case let .aggregateEvent(payload):
            KlaviyoInternal.create(aggregateEvent: payload)
        case let .deepLink(url):
            KlaviyoInternal.handleDeepLink(url: url)
        }
    }
}
