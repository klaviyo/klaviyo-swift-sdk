//
//  KlaviyoSDK.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/4/25.
//

import KlaviyoCore

/// The internal interface for the Klaviyo SDK.
///
/// - Note: Can only be accessed from other modules within the Klaviyo-Swift-SDK package; cannot be accessed from the host app.
package struct KlaviyoInternal {
    /// Create and send an aggregate event.
    /// - Parameter event: the event to be tracked in Klaviyo
    package static func create(aggregateEvent: AggregateEventPayload) {
        dispatchOnMainThread(action: .enqueueAggregateEvent(aggregateEvent))
    }
}
