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
        /// A usable path that isn't cellular (Wi-Fi, wired, or the Simulator); flush at the faster
        /// cadence.
        case reachableViaWiFi
        /// A usable path over cellular; flush at the slower cadence.
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
    init(pathStatus: NWPath.Status, isCellular: Bool) {
        switch pathStatus {
        case .satisfied, .requiresConnection:
            self = isCellular ? .reachableViaWWAN : .reachableViaWiFi
        case .unsatisfied:
            self = .notReachable
        @unknown default:
            self = .notReachable
        }
    }

    /// Wi-Fi wins when a path reports both interfaces, matching the old reachability code, which
    /// only reported cellular when traffic was routed over it.
    init(path: NWPath) {
        let isCellular = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
        self.init(pathStatus: path.status, isCellular: isCellular)
    }
}
