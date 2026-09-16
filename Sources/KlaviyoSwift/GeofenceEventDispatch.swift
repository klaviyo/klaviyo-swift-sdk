//
//  GeofenceEventDispatch.swift
//  klaviyo-swift-sdk
//

import Foundation
import KlaviyoCore

/// KlaviyoSwift entry point for geofence event dispatch, called directly by KlaviyoLocation.
/// Kept in KlaviyoSwift (not on the Core EventDispatching contract) because correct cold/
/// background-launch attribution needs persisted state — anchored by `anonymousId` — that only
/// KlaviyoSwift loads at `.initialize` (`KlaviyoCommands.enqueueEvent` guards on it).
package enum GeofenceEventDispatch {
    /// Enqueue a geofence event, bootstrapping the SDK from the geofence's apiKey if needed.
    /// - once initialization has started (non-empty stored apiKey): ignore the event unless it
    ///   matches the stored key; else enqueue.
    /// - not started: initialize with the geofence apiKey, then enqueue.
    ///
    /// Calls the orchestration functions directly (not via `dispatchOnMainThread`): this method is
    /// already `@MainActor`, so a direct call keeps the state check and the resulting
    /// `initialize`/`enqueueEvent` sequence atomic. Routing through `dispatchOnMainThread` would
    /// defer each call to a separate unstructured task, allowing two near-simultaneous events to
    /// both observe `.uninitialized` (double `initialize`) or to reorder relative to each other.
    @MainActor
    package static func dispatch(event: Event, apiKey: String) {
        if LifecycleState.shared.current != .uninitialized,
           let storedApiKey = SDKConfigStore.shared.current.apiKey, !storedApiKey.isEmpty {
            guard storedApiKey == apiKey else { return }
            KlaviyoCommands.enqueueEvent(event)
        } else {
            KlaviyoCommands.initialize(apiKey)
            KlaviyoCommands.enqueueEvent(event)
        }
    }
}
