//
//  BadgeManager.swift
//
//  Klaviyo Swift SDK
//
//  Created by Belle Lim on 7/15/26.
//

import Foundation
import UIKit
import UserNotifications

//  Self-contained badge-count manager. Owns app-group resolution, the "badgeCount"
//  UserDefaults key, and both directions of badge state (set + sync).
@MainActor
enum BadgeManager {
    // MARK: - Constants

    static let badgeCountKey = "badgeCount"
    static let appGroupInfoDictionaryKey = "klaviyo_app_group"

    // MARK: - Dependencies

    /// The device/OS seams badge operations depend on. Grouped so tests can
    /// override individual closures and `resetToProduction()` can restore every
    /// default in one assignment (`dependencies = .production`).
    @MainActor
    struct Dependencies {
        /// Resolves the app-group UserDefaults suite. Returns nil when no app group is configured.
        var appGroupUserDefaults: () -> UserDefaults?
        /// Sets the native OS badge number. On iOS 16+ this uses the async
        /// UNUserNotificationCenter API; on earlier versions it falls back to the
        /// synchronous UIApplication property (executed on MainActor).
        var setNativeBadge: (Int) async -> Void
        /// Reads the current native OS badge number.
        var currentNativeBadge: () -> Int

        static let production = Dependencies(
            appGroupUserDefaults: {
                guard let appGroup = Bundle.main.object(forInfoDictionaryKey: appGroupInfoDictionaryKey) as? String else {
                    return nil
                }
                return UserDefaults(suiteName: appGroup)
            },
            setNativeBadge: { count in
                if #available(iOS 16.0, *) {
                    try? await UNUserNotificationCenter.current().setBadgeCount(count)
                } else {
                    await MainActor.run {
                        UIApplication.shared.applicationIconBadgeNumber = count
                    }
                }
            },
            currentNativeBadge: {
                UIApplication.shared.applicationIconBadgeNumber
            }
        )
    }

    /// Injectable device/OS seams. Defaults to `.production`; overridden in tests
    /// and restored via `resetToProduction()`.
    static var dependencies = Dependencies.production

    // MARK: - Operations

    /// Sets the OS badge to `count` and persists the value in the app-group
    /// UserDefaults so the notification-service extension can read it.
    ///
    /// If no app group is configured this is a **no-op** (matching the
    /// previous behaviour in `KlaviyoSwiftEnvironment.setBadgeCount`).
    static func setBadgeCount(_ count: Int) async {
        if let spy = setBadgeCountSpy {
            spy(count)
            return
        }
        guard let userDefaults = dependencies.appGroupUserDefaults() else {
            return
        }
        await dependencies.setNativeBadge(count)
        userDefaults.set(count, forKey: badgeCountKey)
    }

    /// Reads the current OS badge number and persists it to the app-group
    /// UserDefaults. Used on app stop / notification response to keep the
    /// extension's stored count in sync with what the OS is displaying.
    ///
    /// If no app group is configured this is a **no-op**.
    static func syncBadgeCount() {
        if let spy = syncBadgeCountSpy {
            spy()
            return
        }
        guard let userDefaults = dependencies.appGroupUserDefaults() else {
            return
        }
        userDefaults.set(dependencies.currentNativeBadge(), forKey: badgeCountKey)
    }
}

// MARK: - Test-only hooks

// TEST-ONLY. The members below exist solely so the reducer / facade test suites
// can observe badge invocations and restore state between tests.
extension BadgeManager {
    /// When non-nil, called by `setBadgeCount(_:)` instead of the production path.
    /// Reset to nil after each test via `resetToProduction()`.
    static var setBadgeCountSpy: ((Int) -> Void)?

    /// When non-nil, called by `syncBadgeCount()` instead of the production path.
    /// Reset to nil after each test via `resetToProduction()`.
    static var syncBadgeCountSpy: (() -> Void)?

    /// Resets the spies and all injected dependencies back to production defaults.
    /// Call this in `setUp` and `tearDown` of any test that installs spies or seams.
    static func resetToProduction() {
        setBadgeCountSpy = nil
        syncBadgeCountSpy = nil
        dependencies = .production
    }
}
