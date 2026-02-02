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

/// Manages the registration of the Klaviyo action button notification category.
///
/// This controller handles:
/// - Registering the single "KLAVIYO_ACTION_BUTTON" category with dynamic actions
/// - Preserving existing categories (including developer-set ones) when updating our category
class KlaviyoCategoryController {
    static let shared = KlaviyoCategoryController()

    /// The category identifier used for all Klaviyo notifications with action buttons
    static let categoryIdentifier = "KLAVIYO_ACTION_BUTTON"

    private init() {}

    // MARK: - Public Methods

    /// Registers the Klaviyo action button notification category with the given actions.
    ///
    /// This method:
    /// 1. Creates a UNNotificationCategory with the provided actions
    /// 2. Merges with existing categories, preserving all other registered categories
    ///
    /// - Parameter actions: Array of notification actions to include in the category
    func registerCategory(actions: [UNNotificationAction]) {
        // Create the category
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
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
    }

    // MARK: - Private Methods

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
