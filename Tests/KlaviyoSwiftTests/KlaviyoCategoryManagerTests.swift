//
//  KlaviyoCategoryManagerTests.swift
//  KlaviyoSwiftTests
//
//  Copyright (c) 2026 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

@testable import KlaviyoSwift
import UserNotifications
import XCTest

final class KlaviyoCategoryManagerTests: XCTestCase {
    private let carousel = KlaviyoCategoryManager.carouselCategoryIdentifier
    private let tappedButton = "\(KlaviyoCategoryManager.categoryIdentifierPrefix)tapped"
    private let displayedButton = "\(KlaviyoCategoryManager.categoryIdentifierPrefix)displayed"
    private let staleButton = "\(KlaviyoCategoryManager.categoryIdentifierPrefix)stale"
    private let developer = "com.example.developer"

    private var allCategories: Set<UNNotificationCategory> {
        Set([carousel, tappedButton, displayedButton, staleButton, developer].map(Self.category))
    }

    private static func category(_ identifier: String) -> UNNotificationCategory {
        UNNotificationCategory(identifier: identifier, actions: [], intentIdentifiers: [])
    }

    private func prunedIdentifiers(removing identifier: String, displayed: Set<String>?) -> Set<String> {
        Set(KlaviyoCategoryManager.prunedCategories(
            allCategories,
            removing: identifier,
            displayedCategoryIdentifiers: displayed
        ).map(\.identifier))
    }

    func testPruningCarouselCategoryKeepsIt() {
        let remaining = prunedIdentifiers(removing: carousel, displayed: [displayedButton])

        XCTAssertEqual(remaining, [carousel, displayedButton, developer])
    }

    func testPruningButtonCategoryRemovesItAndStaleButtonsButKeepsCarousel() {
        let remaining = prunedIdentifiers(removing: tappedButton, displayed: [displayedButton, carousel])

        XCTAssertEqual(remaining, [carousel, displayedButton, developer])
    }

    func testCarouselCategorySurvivesWhenNoNotificationDisplaysIt() {
        let remaining = prunedIdentifiers(removing: tappedButton, displayed: [])

        XCTAssertEqual(remaining, [carousel, developer])
    }

    func testDeliveredFetchTimeoutRemovesOnlyTheTappedCategory() {
        let remaining = prunedIdentifiers(removing: tappedButton, displayed: nil)

        XCTAssertEqual(remaining, [carousel, displayedButton, staleButton, developer])
    }

    func testDeveloperCategoryIsKeptEvenWhenNotDisplayed() {
        let remaining = prunedIdentifiers(removing: staleButton, displayed: [])

        XCTAssertTrue(remaining.contains(developer))
    }
}
