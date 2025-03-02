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
    static var _apiKey: String?
    /// the apiKey (a.k.a. CompanyID) for the current SDK instance.
    package static func apiKey(completion: ((String?) -> Void)? = nil) {
        print("apiKey call")
        if cancellable == nil {
            cancellable = KlaviyoSwiftEnvironment.production.statePublisher()
                .receive(on: DispatchQueue.main)
                .filter { $0.initalizationState == .initialized && $0.apiKey != nil }
                .compactMap(\.apiKey)
                .removeDuplicates()
                .sink(receiveCompletion: { _ in
                    print("nilled")
                    completion?(nil)
                }, receiveValue: {
                    KlaviyoInternal._apiKey = $0
                    // pass in closure
                    print("CALLING CLOSURE WITH API KEY: \(String(describing: $0))")
                    completion?($0)
                })
        }
    }

    /// Create and send an aggregate event.
    /// - Parameter event: the event to be tracked in Klaviyo
    package static func create(aggregateEvent: AggregateEventPayload) {
        dispatchOnMainThread(action: .enqueueAggregateEvent(aggregateEvent))
    }
}
