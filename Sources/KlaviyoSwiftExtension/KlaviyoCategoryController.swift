//
//  KlaviyoCategoryController.swift
//
//  Klaviyo Swift SDK
//
//  Created for Klaviyo
//
//  Copyright (c) 2025 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

import Foundation
import UserNotifications

/// Manages the lifecycle of dynamically registered notification categories.
///
/// This controller handles:
/// - Dynamic category registration per notification
/// - FIFO pruning to maintain 128 category limit
/// - Persistence across app restarts via UserDefaults
/// - Smart merging to avoid overwriting existing categories
class KlaviyoCategoryController {
    static let shared = KlaviyoCategoryController()

    // MARK: - Constants

    /// Maximum number of categories to keep registered (iOS limit is higher, but 128 is plenty)
    private let maxCategories = 128

    /// UserDefaults key for storing registered category IDs
    private let storageKey = "com.klaviyo.registered_categories"

    /// Prefix for all Klaviyo dynamic category IDs
    private let categoryPrefix = "com.klaviyo.dynamic."

    // MARK: - Private Properties

    /// UserDefaults instance (app group aware for badge handling compatibility)
    private var userDefaults: UserDefaults? {
        if let appGroup = Bundle.main.object(forInfoDictionaryKey: "klaviyo_app_group") as? String {
            return UserDefaults(suiteName: appGroup)
        }
        return UserDefaults.standard
    }

    private init() {}

    // MARK: - Public Methods

    /// Registers a notification category with the given notification ID and actions.
    ///
    /// This method:
    /// 1. Generates a unique category ID based on the notification ID
    /// 2. Creates a UNNotificationCategory with the provided actions
    /// 3. Merges with existing categories (without overwriting)
    /// 4. Saves the category ID for persistence
    /// 5. Prunes old categories if limit exceeded
    ///
    /// - Parameters:
    ///   - notificationId: Unique identifier for this notification (from `_k` field)
    ///   - actions: Array of notification actions to include in the category
    /// - Returns: The generated category ID
    func registerCategory(notificationId: String, actions: [UNNotificationAction]) -> String {
        let categoryId = generateCategoryId(notificationId: notificationId)

        // Create the category
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: actions,
            intentIdentifiers: [],
            options: .customDismissAction
        )

        // Get existing categories
        let semaphore = DispatchSemaphore(value: 0)
        var existingCategories: Set<UNNotificationCategory> = []

        UNUserNotificationCenter.current().getNotificationCategories { categories in
            existingCategories = categories
            semaphore.signal()
        }

        // Wait for categories to be fetched (NSE has tight time constraints)
        _ = semaphore.wait(timeout: .now() + 1.0)

        // Merge categories
        let mergedCategories = mergeCategories(existing: existingCategories, new: category)

        // Register the merged set
        UNUserNotificationCenter.current().setNotificationCategories(mergedCategories)

        // Force iOS to refresh its internal category cache
        // This is necessary because iOS caches categories and may not recognize new ones immediately
        UNUserNotificationCenter.current().getNotificationCategories { _ in
            // No-op, just forcing the refresh
        }

        // Save category ID for persistence and pruning
        saveCategoryId(categoryId)

        return categoryId
    }

    /// Generates a unique category ID for the given notification ID.
    ///
    /// Format: `com.klaviyo.dynamic.<notificationId>`
    ///
    /// - Parameter notificationId: The notification's unique identifier
    /// - Returns: A category identifier string
    func generateCategoryId(notificationId: String) -> String {
        return categoryPrefix + notificationId
    }

    // MARK: - Private Methods

    /// Merges a new category with existing categories without overwriting.
    ///
    /// - Parameters:
    ///   - existing: Set of currently registered categories
    ///   - new: New category to add
    /// - Returns: Merged set of categories
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

    /// Saves a category ID to persistent storage and triggers pruning if needed.
    ///
    /// - Parameter categoryId: The category ID to save
    private func saveCategoryId(_ categoryId: String) {
        guard let defaults = userDefaults else { return }

        // Get existing category IDs
        var categoryIds = getRegisteredCategoryIds()

        // Remove if already exists (to update position in FIFO queue)
        categoryIds.removeAll { $0 == categoryId }

        // Add to end (most recent)
        categoryIds.append(categoryId)

        // Prune if over limit
        if categoryIds.count > maxCategories {
            let idsToRemove = Array(categoryIds.prefix(categoryIds.count - maxCategories))
            pruneCategories(idsToRemove)
            categoryIds = Array(categoryIds.suffix(maxCategories))
        }

        // Save updated list
        defaults.set(categoryIds, forKey: storageKey)
        defaults.synchronize()
    }

    /// Retrieves the list of registered category IDs from persistent storage.
    ///
    /// - Returns: Array of category ID strings (oldest to newest)
    func getRegisteredCategoryIds() -> [String] {
        guard let defaults = userDefaults else { return [] }
        return defaults.stringArray(forKey: storageKey) ?? []
    }

    /// Removes the specified category IDs from the notification center.
    ///
    /// This method fetches all categories, filters out the ones to remove,
    /// and re-registers the remaining categories.
    ///
    /// - Parameter categoryIds: Array of category IDs to remove
    private func pruneCategories(_ categoryIds: [String]) {
        guard !categoryIds.isEmpty else { return }

        let semaphore = DispatchSemaphore(value: 0)
        var existingCategories: Set<UNNotificationCategory> = []

        UNUserNotificationCenter.current().getNotificationCategories { categories in
            existingCategories = categories
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 1.0)

        // Filter out categories to remove
        let categoryIdsSet = Set(categoryIds)
        let filteredCategories = existingCategories.filter { !categoryIdsSet.contains($0.identifier) }

        // Re-register without the pruned categories
        UNUserNotificationCenter.current().setNotificationCategories(filteredCategories)
    }
}
