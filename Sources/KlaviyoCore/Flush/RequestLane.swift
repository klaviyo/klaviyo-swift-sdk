//
//  RequestLane.swift
//  klaviyo-swift-sdk
//
//  Lane-scheduler POC.
//

import Foundation

/// A scheduling lane: an independent FIFO track through `RequestQueue`. Lanes share the single
/// persisted `QueueStore` (a lane is derived from each request's endpoint, never stored), but each
/// has its own lease, retry bookkeeping, and backoff gate, so a retrying lane never delays another.
public enum RequestLane: CaseIterable {
    /// Identity mutation traffic: profile creates/updates, push-token registration/unregistration,
    /// and subscriptions. Profile changes folded into a push-token request ride in this lane.
    case identity
    /// Event traffic: `/client/events`.
    case events
    /// Engagement traffic: onsite aggregate events and tracking-link click logging.
    case engagement
}

extension KlaviyoEndpoint {
    /// The lane this endpoint's requests are scheduled on. This is the single place endpoint →
    /// lane mapping lives, so reclassifying an endpoint is a one-line change here.
    public var lane: RequestLane {
        switch self {
        case .createProfile,
             .registerPushToken,
             .unregisterPushToken,
             .createSubscription:
            return .identity
        case .createEvent:
            return .events
        case .aggregateEvent,
             .logTrackingLinkClicked:
            return .engagement
        // Not queue-scheduled: `resolveDestinationURL` and `fetchGeofences` are sent directly
        // (see `SDKRequestIterator`), never enqueued to `QueueStore`. Mapped to a lane only so the
        // switch stays total; the value is unused in practice.
        case .resolveDestinationURL,
             .fetchGeofences:
            return .engagement
        }
    }
}
