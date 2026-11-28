//
//  Reachability.swift
//  klaviyo-swift-sdk
//

import Foundation
import Network

// swiftlint:disable identifier_name
/// Posted by ``NetworkPathMonitor`` whenever the mapped ``Reachability/NetworkStatus`` changes.
/// Observers read the new value from `environment.reachabilityStatus()`.
public let ReachabilityChangedNotification = NSNotification.Name("ReachabilityChangedNotification")
// swiftlint:enable identifier_name

/// Namespace for the SDK's coarse network-connectivity status, derived from `NWPath`.
public enum Reachability {
    /// Connectivity as it drives the request queue's flush cadence.
    public enum NetworkStatus: Sendable, CustomStringConvertible {
        /// No usable network path.
        case notReachable
        /// A usable path that is neither expensive nor constrained (flush at the faster cadence).
        case reachableViaWiFi
        /// A usable path that is expensive (cellular, personal hotspot) or constrained (Low Data
        /// Mode); flush at the slower cadence.
        case reachableViaWWAN

        public var description: String {
            switch self {
            case .reachableViaWWAN: return "Cellular"
            case .reachableViaWiFi: return "WiFi"
            case .notReachable: return "No Connection"
            }
        }
    }
}

extension Reachability.NetworkStatus {
    /// Maps an `NWPath` snapshot to a ``Reachability/NetworkStatus``.
    ///
    /// `.requiresConnection` (e.g. an on-demand VPN) counts as reachable: the path comes up once a
    /// connection is attempted, so treating it as offline would stop the queue from ever making
    /// the request that activates it.
    init(pathStatus: NWPath.Status, isExpensive: Bool, isConstrained: Bool) {
        switch pathStatus {
        case .satisfied, .requiresConnection:
            self = isExpensive || isConstrained ? .reachableViaWWAN : .reachableViaWiFi
        case .unsatisfied:
            self = .notReachable
        @unknown default:
            self = .notReachable
        }
    }

    /// iOS marks cellular and a Wi-Fi link to a personal hotspot as expensive, and a network in Low
    /// Data Mode as constrained; all of them get the slower cadence.
    init(path: NWPath) {
        self.init(pathStatus: path.status, isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }
}
