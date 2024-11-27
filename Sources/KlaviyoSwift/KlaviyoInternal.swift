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
    static var cancellable: Cancellable?
    /// the apiKey (a.k.a. CompanyID) for the current SDK instance.
    /// - Parameter completion: completion hanlder that will be called when apiKey is avaialble after SDK is initilized
    @MainActor
    package static func apiKey(completion: @escaping ((String?) -> Void)) {
        if cancellable == nil {
            cancellable = KlaviyoSwiftEnvironment.production.statePublisher()
                .receive(on: DispatchQueue.main)
                .filter { $0.initalizationState == .initialized }
                .compactMap(\.apiKey)
                .removeDuplicates()
                .prefix(1)
                .sink(receiveValue: {
                    completion($0)
                    cancellable = nil
                })
        }
    }

    /// Create and send an aggregate event.
    /// - Parameter event: the event to be tracked in Klaviyo
    package static func create(aggregateEvent: AggregateEventPayload) {
        Task {
            await dispatchStoreAction(action: .enqueueAggregateEvent(aggregateEvent))
        }
    }
}
