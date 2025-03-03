//
//  KlaviyoSDK.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/4/25.
//

import Combine
import Foundation
import KlaviyoCore

/// The internal interface for the Klaviyo SDK.
///
/// - Note: Can only be accessed from other modules within the Klaviyo-Swift-SDK package; cannot be accessed from the host app.
package struct KlaviyoInternal {
    /// the apiKey (a.k.a. CompanyID) for the current SDK instance.
    /// - Parameter completion: completion hanlder that will be called when apiKey is avaialble after SDK is initilized
    package static func apiKey() -> any Publisher<String, Never> {
        KlaviyoSwiftEnvironment.production.statePublisher()
            .receive(on: DispatchQueue.main)
            .filter { $0.initalizationState == .initialized }
            .compactMap(\.apiKey)
            .removeDuplicates()
            .first()
    }

    /// Create and send an aggregate event.
    /// - Parameter event: the event to be tracked in Klaviyo
    package static func create(aggregateEvent: AggregateEventPayload) {
        dispatchOnMainThread(action: .enqueueAggregateEvent(aggregateEvent))
    }
}
