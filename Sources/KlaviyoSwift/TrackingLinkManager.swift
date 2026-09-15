//
//  TrackingLinkManager.swift
//
//  Klaviyo Swift SDK
//
//  Created by Belle Lim on 7/20/26.
//

import Foundation
import KlaviyoCore
import OSLog

/// Owns the tracking-link (click-tracking) resolution flow.
///
/// Today this manager holds only the state-free work — the network resolve,
/// decode, logging, and navigation. The reducer keeps two thin cases
/// (`trackingLinkReceived`, `trackingLinkResolutionFailed`) solely
/// because they touch reducer-owned state: reading identity to build the
/// `ProfilePayload`, and enqueuing the click-log request on failure.
///
/// Once identity and the request queue become canonical in `KlaviyoCore` (an
/// `IdentityStore` that is the source of truth and a queue that can be enqueued
/// into from anywhere), both of those reducer cases can be folded into this
/// manager: it will read identity from `IdentityStore`, enqueue the failure
/// request directly, and be invoked straight from the SDK entry point — at which
/// point the two reducer cases are deleted.
enum TrackingLinkManager {
    /// The result of resolving a Klaviyo tracking link to its destination.
    enum Outcome: Equatable {
        case resolved(URL)
        case failed
    }

    /// Resolves a Klaviyo tracking link to its destination URL via the engtrack
    /// service. Returns `.resolved` with the destination on success, or `.failed`
    /// if the request or decode fails (the caller logs the click via the failure
    /// path).
    static func resolveDestination(
        trackingLink: URL,
        profileInfo: ProfilePayload
    ) async -> Outcome {
        do {
            let endpoint = KlaviyoEndpoint.resolveDestinationURL(
                trackingLink: trackingLink,
                profileInfo: profileInfo
            )
            let klaviyoRequest = KlaviyoRequest(endpoint: endpoint)
            let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: endpoint.maxRetries)
            let result = await environment.klaviyoAPI.send(klaviyoRequest, attemptInfo)

            switch result {
            case let .success(data):
                let response: TrackingLinkDestinationResponse = try environment.decoder.decode(data)
                let destinationURL = response.destinationLink
                if #available(iOS 14.0, *) {
                    Logger.stateLogger.info("Successfully resolved tracking link destination. Destination URL: '\(destinationURL.absoluteString)'")
                }
                return .resolved(destinationURL)
            case let .failure(error):
                if #available(iOS 14.0, *) {
                    Logger.stateLogger.warning("Unable to resolve tracking link destination; error:\n'\(error)'")
                }
                return .failed
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.stateLogger.warning("Unable to resolve tracking link destination; error:\n'\(error)'")
            }
            return .failed
        }
    }
}
