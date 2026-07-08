//
//  GeofenceEventDispatch.swift
//  klaviyo-swift-sdk
//

import Foundation
import KlaviyoCore

/// KlaviyoSwift entry point for geofence event dispatch, called directly by KlaviyoLocation.
/// Kept in KlaviyoSwift (not on the Core EventDispatching contract) because correct cold/
/// background-launch attribution needs persisted state — anchored by `anonymousId` — that only
/// KlaviyoSwift loads at `.initialize` (`StateManagement` `.enqueueEvent` guards on it).
package enum GeofenceEventDispatch {
    /// Enqueue a geofence event, bootstrapping the SDK from the geofence's apiKey if needed.
    /// - initialized with a non-empty apiKey: ignore the event unless it matches; else enqueue.
    /// - not initialized: initialize with the geofence apiKey, then enqueue.
    @MainActor
    package static func dispatch(event: Event, apiKey: String) {
        let state = klaviyoSwiftEnvironment.state()
        if state.initalizationState == .initialized,
           let storedApiKey = state.apiKey, !storedApiKey.isEmpty {
            guard storedApiKey == apiKey else { return }
            dispatchOnMainThread(action: .enqueueEvent(event))
        } else {
            dispatchOnMainThread(action: .initialize(apiKey))
            dispatchOnMainThread(action: .enqueueEvent(event))
        }
    }
}
