//
//  GeofenceCooldownTracker.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

import Foundation
import KlaviyoCore
import KlaviyoSwift

/// Manages geofence transition cooldown periods to prevent duplicate
/// events emitted from CoreLocation.
///
/// This tracker enforces a cooldown period per geofence and transition
/// type to filter out noise while allowing legitimate events. Cooldown data
/// is stored in UserDefaults with automatic cleanup of stale entries.
class GeofenceCooldownTracker {
    /// Key for storing geofence transition cooldown timestamps as a dictionary
    private static let geofenceCooldownsKey = "geofence_cooldowns"

    /// Cooldown period for geofence transitions in seconds (60 seconds)
    /// Prevents duplicate events emitted from CoreLocation.
    private static let geofenceTransitionCooldown: TimeInterval = 60.0

    /// Check if a geofence transition is allowed (not in cooldown period)
    ///
    /// - Parameters:
    ///   - geofenceId: The geofence ID to check
    ///   - transition: The transition type to check
    /// - Returns: true if the event should be created (cooldown elapsed or no previous event), false otherwise
    func isAllowed(geofenceId: String, transition: Event.EventName.LocationEvent) -> Bool {
        let cooldownMap = loadCooldownMap()
        let mapKey = getCooldownMapKey(geofenceId: geofenceId, transition: transition)

        guard let lastTransitionTime = cooldownMap[mapKey] else {
            // No previous transition recorded, allow it
            return true
        }

        let currentTime = environment.date().timeIntervalSince1970
        let timeSinceLastTransition = currentTime - lastTransitionTime

        // Allow if cooldown period has elapsed
        return timeSinceLastTransition >= Self.geofenceTransitionCooldown
    }

    /// Record a geofence transition timestamp
    ///
    /// - Parameters:
    ///   - geofenceId: The geofence ID
    ///   - transition: The transition type
    func recordTransition(geofenceId: String, transition: Event.EventName.LocationEvent) {
        var cooldownMap = loadCooldownMap()
        let mapKey = getCooldownMapKey(geofenceId: geofenceId, transition: transition)
        let currentTime = environment.date().timeIntervalSince1970

        cooldownMap[mapKey] = currentTime
        saveCooldownMap(cooldownMap)
    }

    /// Generate a unique key for a geofence and transition combination
    private func getCooldownMapKey(geofenceId: String, transition: Event.EventName.LocationEvent) -> String {
        "\(geofenceId):\(transition)"
    }

    /// Load the cooldown map from UserDefaults
    private func loadCooldownMap() -> [String: TimeInterval] {
        guard let data = UserDefaults.standard.data(forKey: Self.geofenceCooldownsKey),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var map: [String: TimeInterval] = [:]

        // Convert JSON to TimeInterval dictionary
        for (key, value) in json {
            if let timestamp = value as? TimeInterval {
                map[key] = timestamp
            } else if let timestampDouble = value as? Double {
                map[key] = timestampDouble
            }
        }

        return map
    }

    /// Save the cooldown map to UserDefaults, filtering out stale entries before saving
    private func saveCooldownMap(_ map: [String: TimeInterval]) {
        let currentTime = environment.date().timeIntervalSince1970
        var cleanedMap: [String: TimeInterval] = [:]

        // Filter out stale entries (older than cooldown period)
        for (key, timestamp) in map {
            let age = currentTime - timestamp
            if age < Self.geofenceTransitionCooldown {
                cleanedMap[key] = timestamp
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: cleanedMap) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.geofenceCooldownsKey)
    }
}
