//
//  DwellTimerTracker.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

import Foundation
import KlaviyoCore
import KlaviyoSwift
import OSLog

/// Manages geofence dwell timer persistence and recovery.
///
/// This tracker handles persistence of dwell timer data to UserDefaults,
/// allowing recovery of expired timers when the app terminates and relaunches.
/// The actual Timer objects are managed by KlaviyoLocationManager.
class DwellTimerTracker {
    private static let dwellTimersKey = "klaviyo_dwell_timers"

    private struct DwellTimerData: Codable {
        let startTime: TimeInterval
        let duration: Int
    }

    /// Save dwell timer data to UserDefaults
    ///
    /// - Parameters:
    ///   - geofenceId: The geofence location ID
    ///   - startTime: The timestamp when the timer started
    ///   - duration: The duration of the timer in seconds
    func saveTimer(geofenceId: String, startTime: TimeInterval, duration: Int) {
        var timerMap = loadTimers()
        timerMap[geofenceId] = DwellTimerData(startTime: startTime, duration: duration)

        guard let data = try? JSONEncoder().encode(timerMap) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.dwellTimersKey)
    }

    /// Remove dwell timer data from UserDefaults
    ///
    /// - Parameter geofenceId: The geofence location ID
    func removeTimer(geofenceId: String) {
        var timerMap = loadTimers()
        timerMap.removeValue(forKey: geofenceId)

        guard let data = try? JSONEncoder().encode(timerMap) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.dwellTimersKey)
    }

    /// Load all persisted dwell timers from UserDefaults
    ///
    /// - Returns: Dictionary mapping geofence IDs to their timer data
    private func loadTimers() -> [String: DwellTimerData] {
        guard let data = UserDefaults.standard.data(forKey: Self.dwellTimersKey),
              let timerMap = try? JSONDecoder().decode([String: DwellTimerData].self, from: data) else {
            return [:]
        }
        return timerMap
    }

    /// Check for expired timers and returns them
    ///
    /// - Parameter activeTimerIds: Set of geofence IDs that currently have active in-memory timers
    /// - Returns: Array of expired timer information (geofence ID and duration)
    func getExpiredTimers(activeTimerIds: Set<String>) -> [(geofenceId: String, duration: Int)] {
        let timerMap = loadTimers()
        guard !timerMap.isEmpty else { return [] }

        let currentTime = environment.date().timeIntervalSince1970
        var expiredTimers: [(geofenceId: String, duration: Int)] = []
        var timersToRemove: [String] = []

        for (geofenceId, timerData) in timerMap {
            // If timer exists in memory, it's already active - remove from persistence to avoid duplication
            if activeTimerIds.contains(geofenceId) {
                timersToRemove.append(geofenceId)
                continue
            }

            let age = currentTime - timerData.startTime

            // Check if timer expired (elapsed >= duration)
            if age >= TimeInterval(timerData.duration) {
                timersToRemove.append(geofenceId)
                expiredTimers.append((geofenceId: geofenceId, duration: timerData.duration))

                if #available(iOS 14.0, *) {
                    Logger.geoservices.info("🕐 Found expired dwell timer for region \(geofenceId) (expired while app was terminated)")
                }
            }
        }

        // Clean up all timers that need to be removed
        for geofenceId in timersToRemove {
            removeTimer(geofenceId: geofenceId)
        }

        return expiredTimers
    }
}
