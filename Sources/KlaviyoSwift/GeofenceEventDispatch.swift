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
    ///
    /// Sends go directly to `klaviyoSwiftEnvironment` (not via `dispatchOnMainThread`): this method
    /// is already `@MainActor`, so a direct send keeps the state check and the resulting
    /// `.initialize`/`.enqueueEvent` sequence atomic. Routing through `dispatchOnMainThread` would
    /// defer each send to a separate unstructured task, allowing two near-simultaneous events to
    /// both observe `.uninitialized` (double `.initialize`) or to reorder relative to each other.
    @MainActor
    package static func dispatch(event: Event, apiKey: String) {
        let state = klaviyoSwiftEnvironment.state()
        if state.initalizationState == .initialized,
           let storedApiKey = state.apiKey, !storedApiKey.isEmpty {
            guard storedApiKey == apiKey else { return }
            _ = klaviyoSwiftEnvironment.send(.enqueueEvent(event))
        } else {
            _ = klaviyoSwiftEnvironment.send(.initialize(apiKey))
            _ = klaviyoSwiftEnvironment.send(.enqueueEvent(event))
        }
    }
}
