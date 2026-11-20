//
//  KlaviyoCategoryManager.swift
//
//
//  Created by Belle Lim on 1/20/26.
//

// NOTE: pruneCategory is intentionally not duplicated in KlaviyoSwiftExtension.
// That target carries a separate register-only KlaviyoCategoryManager
// (Sources/KlaviyoSwiftExtension/KlaviyoCategoryManager.swift) because it cannot
// depend on the main app (NSE/share-extension sandbox restriction). Pruning is
// only needed in the main app (KlaviyoSwift) and lives exclusively here.

import Foundation
import OSLog
import UserNotifications

/// Manages pruning of stale Klaviyo notification categories in the main app.
///
/// Registration is handled by KlaviyoSwiftExtension's copy of this class (NSE context).
/// This class is responsible only for pruning stale categories after a notification is
/// opened or dismissed from the main app.
class KlaviyoCategoryManager {
    static let shared = KlaviyoCategoryManager()

    /// Prefix used for all Klaviyo notification category identifiers
    static let categoryIdentifierPrefix = "com.klaviyo.button."

    /// Static category shared by every carousel push. A notification content extension can only
    /// match exact category identifiers listed in its Info.plist, so this one is never pruned.
    static let carouselCategoryIdentifier = "com.klaviyo.carousel"

    /// Serial queue to ensure thread-safe category updates
    private let queue = DispatchQueue(label: "com.klaviyo.category.registration", qos: .userInitiated)

    private init() {}

    // MARK: - Public Methods

    /// Removes a notification category from the registered categories and prunes any other stale categories.
    ///
    /// This method:
    /// 1. Fetches all currently registered categories
    /// 2. Removes the category with the matching identifier
    /// 3. Checks for and removes any other stale Klaviyo categories that are no longer in the Notification Center
    /// 4. Updates the registered categories, preserving all other categories
    ///
    /// - Parameter categoryIdentifier: The identifier of the category to remove
    func pruneCategory(categoryIdentifier: String) {
        queue.sync {
            let (existingCategories, categoriesFetchTimedOut) = fetchExistingCategories()
            if categoriesFetchTimedOut {
                if #available(iOS 14.0, *) {
                    Logger.notifications.warning("Could not retrieve existing categories. Cannot safely prune category '\(categoryIdentifier)'.")
                }
                return
            }

            // Check Notification Center for any other stale categories that are no longer displayed.
            // If that fetch times out, only the specific category is removed.
            let (deliveredNotifications, notificationsFetchTimedOut) = fetchDeliveredNotifications()
            let displayedCategoryIdentifiers = notificationsFetchTimedOut
                ? nil
                : Set(deliveredNotifications.map(\.request.content.categoryIdentifier))

            let updatedCategories = Self.prunedCategories(
                existingCategories,
                removing: categoryIdentifier,
                displayedCategoryIdentifiers: displayedCategoryIdentifiers
            )

            if #available(iOS 14.0, *) {
                let removedCount = existingCategories.count - updatedCategories.count
                Logger.notifications.info("Pruned \(removedCount) category/categories after '\(categoryIdentifier)'. (Total remaining: \(updatedCategories.count))")
            }

            UNUserNotificationCenter.current().setNotificationCategories(updatedCategories)
        }
    }

    /// Computes the categories to keep after a notification with `categoryIdentifier` is opened or dismissed.
    ///
    /// - Removes `categoryIdentifier`, plus any `com.klaviyo.button.*` category not used by a displayed
    ///   notification when `displayedCategoryIdentifiers` is known.
    /// - Never removes non-Klaviyo categories or the shared carousel category.
    ///
    /// - Parameters:
    ///   - existingCategories: The currently registered categories
    ///   - categoryIdentifier: The category of the notification that was opened or dismissed
    ///   - displayedCategoryIdentifiers: Categories of notifications still in Notification Center,
    ///     or `nil` if they couldn't be fetched
    static func prunedCategories(
        _ existingCategories: Set<UNNotificationCategory>,
        removing categoryIdentifier: String,
        displayedCategoryIdentifiers: Set<String>?
    ) -> Set<UNNotificationCategory> {
        existingCategories.filter { category in
            let identifier = category.identifier
            if identifier == carouselCategoryIdentifier {
                return true
            }
            if identifier == categoryIdentifier {
                return false
            }
            guard let displayedCategoryIdentifiers,
                  identifier.hasPrefix(categoryIdentifierPrefix) else {
                return true
            }
            return displayedCategoryIdentifiers.contains(identifier)
        }
    }

    // MARK: - Private Methods

    /// Fetches existing notification categories with timeout handling.
    ///
    /// - Returns: A tuple containing the set of existing categories and a boolean indicating if the fetch timed out
    private func fetchExistingCategories() -> (Set<UNNotificationCategory>, Bool) {
        let semaphore = DispatchSemaphore(value: 0)
        var existingCategories: Set<UNNotificationCategory> = []
        var fetchTimedOut = false

        UNUserNotificationCenter.current().getNotificationCategories { categories in
            existingCategories = categories
            semaphore.signal()
        }

        // Wait for categories to be fetched
        let result = semaphore.wait(timeout: .now() + 1.0)
        if result == .timedOut {
            fetchTimedOut = true
        }

        return (existingCategories, fetchTimedOut)
    }

    /// Fetches delivered notifications from the Notification Center with timeout handling.
    ///
    /// - Returns: A tuple containing the array of delivered notifications and a boolean indicating if the fetch timed out
    private func fetchDeliveredNotifications() -> ([UNNotification], Bool) {
        let semaphore = DispatchSemaphore(value: 0)
        var deliveredNotifications: [UNNotification] = []
        var fetchTimedOut = false

        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            deliveredNotifications = notifications
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + 1.0)
        if result == .timedOut {
            fetchTimedOut = true
        }

        return (deliveredNotifications, fetchTimedOut)
    }
}
