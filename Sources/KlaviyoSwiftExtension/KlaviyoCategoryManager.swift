//
//  KlaviyoCategoryManager.swift
//

// NOTE: KlaviyoCore carries the authoritative copy of this class
// (Sources/KlaviyoCore/KlaviyoCategoryManager.swift), which also includes
// pruneCategory. This register-only copy exists because KlaviyoSwiftExtension
// cannot depend on KlaviyoCore (NSE/share-extension sandbox restriction).
// The two copies are intentionally kept in sync. If you change registerCategory,
// fetchExistingCategories, or mergeCategories here, mirror the changes there.

import Foundation
import OSLog
import UserNotifications

/// Manages the registration of the Klaviyo action button notification category.
///
/// This manager handles:
/// - Registering unique categories per notification with dynamic actions
/// - Preserving existing categories (including developer-set ones) when adding new categories
class KlaviyoCategoryManager {
    static let shared = KlaviyoCategoryManager()

    /// Prefix used for all Klaviyo notification category identifiers
    static let categoryIdentifierPrefix = "com.klaviyo.button."

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
    func registerCategory(categoryIdentifier: String, actions: [UNNotificationAction]) {
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
                    Logger.notifications.warning("Could not retrieve existing categories. Prioritizing and setting the incoming category. Existing categories may be lost.")
                }
                mergedCategories = [category]
            } else {
                // Merge categories normally
                mergedCategories = self.mergeCategories(existing: existingCategories, new: category)
            }

            // Register the merged set
            if #available(iOS 14.0, *) {
                Logger.notifications.warning("Registered new notification category '\(categoryIdentifier)'. Total categories: \(mergedCategories.count)")
            }
            UNUserNotificationCenter.current().setNotificationCategories(mergedCategories)
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
        merged = merged.filter { $0.identifier != new.identifier }
        merged.insert(new)
        return merged
    }
}
