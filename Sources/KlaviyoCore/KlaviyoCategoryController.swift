//
//  KlaviyoCategoryController.swift
//
//
//  Created by Belle Lim on 1/20/26.
//

import Foundation
import OSLog
import UserNotifications

/// Manages the registration of the Klaviyo action button notification category.
///
/// This controller handles:
/// - Registering unique categories per notification with dynamic actions
/// - Preserving existing categories (including developer-set ones) when adding new categories
public class KlaviyoCategoryController {
    public static let shared = KlaviyoCategoryController()

    /// Prefix used for all Klaviyo notification category identifiers
    public static let categoryIdentifierPrefix = "com.klaviyo.button."

    /// Serial queue to ensure thread-safe category registration
    private let queue = DispatchQueue(label: "com.klaviyo.category.registration", qos: .userInitiated)

    private init() {}

    // MARK: - Public Methods

    /// Registers a Klaviyo action button notification category with the given actions.
    ///
    /// Each notification should use a unique category identifier to prevent race conditions
    /// where multiple notifications with different buttons overwrite each other's category.
    /// This is a risk when either multiple notifications arrive simultaneously or multiple
    /// notifications with action buttons sit in the Notification Center and are opened later.
    ///
    /// This method:
    /// 1. Creates a UNNotificationCategory with the provided actions and identifier
    /// 2. Merges with existing categories, preserving all other registered categories
    ///
    /// - Parameters:
    ///   - categoryIdentifier: Unique identifier for this notification's category
    ///   - actions: Array of notification actions to include in the category
    public func registerCategory(categoryIdentifier: String, actions: [UNNotificationAction]) {
        // Use serial queue to ensure thread-safe registration when multiple notifications arrive simultaneously
        queue.sync {
            // Create the category
            let category = UNNotificationCategory(
                identifier: categoryIdentifier,
                actions: actions,
                intentIdentifiers: [],
                options: .customDismissAction
            )

            // Get existing categories
            let (existingCategories, fetchTimedOut) = fetchExistingCategories()

            // If fetch timed out, proceed with empty set to avoid blocking
            // The category will still be registered, but we won't preserve existing ones
            // This is acceptable since NSE has tight time constraints
            let mergedCategories: Set<UNNotificationCategory>
            if fetchTimedOut {
                // If we timed out, just register the new category
                // This is a trade-off: we might lose some existing categories, but we avoid blocking
                if #available(iOS 14.0, *) {
                    Logger.actionButtons.warning("Could not retrieve existing categories. Prioritizing and setting the incoming category. Existing categories may be lost.")
                }
                mergedCategories = [category]
            } else {
                // Merge categories normally
                mergedCategories = self.mergeCategories(existing: existingCategories, new: category)
            }

            // Register the merged set
            if #available(iOS 14.0, *) {
                Logger.actionButtons.warning("Registered new notification category '\(categoryIdentifier)'. Total categories: \(mergedCategories.count)")
            }
            UNUserNotificationCenter.current().setNotificationCategories(mergedCategories)
        }
    }

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
                    Logger.actionButtons.warning("Could not retrieve existing categories. Cannot safely prune category '\(categoryIdentifier)'.")
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
                        Logger.actionButtons.info("Removed category '\(categoryIdentifier)' and \(staleCategories.count) stale category/categories. (Total remaining: \(updatedCategories.count))")
                    }
                } else {
                    if #available(iOS 14.0, *) {
                        Logger.actionButtons.info("Removed category '\(categoryIdentifier)'. (Total left: \(updatedCategories.count))")
                    }
                }
            } else {
                // If we can't fetch delivered notifications, still remove the specific category
                if #available(iOS 14.0, *) {
                    Logger.actionButtons.info("Removed category '\(categoryIdentifier)'. (Total left: \(updatedCategories.count))")
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

        // Wait for categories to be fetched (NSE has tight time constraints)
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

    /// Merges a new category with existing categories.
    ///
    /// This ensures that when we call `setNotificationCategories()`, we don't remove
    /// categories that developers have already registered. We only update/replace
    /// categories with the same identifier as the new one.
    ///
    /// - Parameters:
    ///   - existing: Set of currently registered categories
    ///   - new: New category to add or update
    /// - Returns: Merged set of categories with the new category added/updated
    private func mergeCategories(
        existing: Set<UNNotificationCategory>,
        new: UNNotificationCategory
    ) -> Set<UNNotificationCategory> {
        var merged = existing

        // Remove any existing category with the same ID (update case)
        merged = merged.filter { $0.identifier != new.identifier }

        // Add the new category
        merged.insert(new)

        return merged
    }
}
