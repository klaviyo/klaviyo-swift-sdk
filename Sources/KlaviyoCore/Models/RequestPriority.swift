//
//  RequestPriority.swift
//
//
//  Created by Isobelle Lim on 7/21/26.
//

/// The priority level for a Klaviyo request.
///
/// High-priority requests (e.g., opened-push, geofence events) are front-inserted in the
/// queue and trigger an immediate flush. Standard requests follow regular flush intervals.
public enum RequestPriority: String, Codable, Equatable {
    /// Default priority — request is appended to the queue and flushed on the regular interval.
    case standard

    /// High priority — request is inserted at the front of the queue and triggers an immediate flush.
    case high
}
