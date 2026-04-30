//
//  KlaviyoCategoryManager.swift
//
//
//  Created by Belle Lim on 1/20/26.
//

// NOTE: pruneCategory is intentionally not duplicated in KlaviyoSwiftExtension.
// That target carries a separate register-only KlaviyoCategoryManager
// (Sources/KlaviyoSwiftExtension/KlaviyoCategoryManager.swift) because it cannot
// depend on KlaviyoCore (NSE/share-extension sandbox restriction). Pruning is
// only needed in the main app (KlaviyoSwift) and lives exclusively here.

import Foundation
import OSLog
import UserNotifications

/// Manages pruning of stale Klaviyo notification categories in the main app.
///
/// Registration is handled by KlaviyoSwiftExtension's copy of this class (NSE context).
/// This class is responsible only for pruning stale categories after a notification is
/// opened or dismissed from the main app.
public class KlaviyoCategoryManager {
    public static let shared = KlaviyoCategoryManager()

    /// Prefix used for all Klaviyo notification category identifiers
    public static let categoryIdentifierPrefix = "com.klaviyo.button."

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
    public func pruneCategory(categoryIdentifier: String) {
        queue.sync {
            let (existingCategories, categoriesFetchTimedOut) = fetchExistingCategories()
            if categoriesFetchTimedOut {
                if #available(iOS 14.0, *) {
                    Logger.notifications.warning("Could not retrieve existing categories. Cannot safely prune category '\(categoryIdentifier)'.")
                }
                return
            }

            // First, remove the category we know is no longer being used
            var updatedCategories = existingCategories.filter { $0.identifier != categoryIdentifier }

            // Then check for all notifications in Notification Center for any other stale categories that are no longer displayed
            let (deliveredNotifications, notificationsFetchTimedOut) = fetchDeliveredNotifications()

            if !notificationsFetchTimedOut {
                // Extract Klaviyo category identifiers from displayed notifications
                let displayedCategoryIdentifiers = Set(deliveredNotifications.compactMap { notification in
                    let notificationCategoryId = notification.request.content.categoryIdentifier
                    return notificationCategoryId.hasPrefix(Self.categoryIdentifierPrefix) ? notificationCategoryId : nil
                })

                // Find Klaviyo categories that are no longer referenced by any notification in the Notification Center
                let klaviyoCategories = updatedCategories.filter { $0.identifier.hasPrefix(Self.categoryIdentifierPrefix) }
                let staleCategories = klaviyoCategories.filter { !displayedCategoryIdentifiers.contains($0.identifier) }

                if !staleCategories.isEmpty {
                    let staleCategoryIdentifiers = Set(staleCategories.map(\.identifier))
                    updatedCategories = updatedCategories.filter { !staleCategoryIdentifiers.contains($0.identifier) }

                    if #available(iOS 14.0, *) {
                        Logger.notifications.info("Removed category '\(categoryIdentifier)' and \(staleCategories.count) stale category/categories. (Total remaining: \(updatedCategories.count))")
                    }
                } else {
                    if #available(iOS 14.0, *) {
                        Logger.notifications.info("Removed category '\(categoryIdentifier)'. (Total left: \(updatedCategories.count))")
                    }
                }
            } else {
                // If we can't fetch delivered notifications, still remove the specific category
                if #available(iOS 14.0, *) {
                    Logger.notifications.info("Removed category '\(categoryIdentifier)'. (Total left: \(updatedCategories.count))")
                }
            }

            UNUserNotificationCenter.current().setNotificationCategories(updatedCategories)
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
