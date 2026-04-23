//
//  InAppWindowManagerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Evan Masseau on 4/22/26.
//

@testable import KlaviyoForms
import UIKit
import XCTest

final class InAppWindowManagerTests: XCTestCase {
    // A representative iPhone-ish layout for tests.
    private let screenBounds = CGRect(x: 0, y: 0, width: 400, height: 800)
    private let safeArea = UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)

    private func layout(
        position: FormPosition,
        width: CGFloat = 300,
        height: CGFloat = 200,
        offsets: Offsets = .zero,
        addSafeAreaInsetsToOffsets: Bool = true
    ) -> FormLayout {
        FormLayout(
            position: position,
            width: Dimension(value: Double(width), unit: .fixed),
            height: Dimension(value: Double(height), unit: .fixed),
            offsets: offsets,
            addSafeAreaInsetsToOffsets: addSafeAreaInsetsToOffsets
        )
    }

    // MARK: - addSafeAreaInsetsToOffsets=true (default) preserves existing behavior

    func testAddSafeAreaInsetsTrueIncludesSafeAreaForCornerAndCenteredPositions() {
        let offsets = Offsets(top: 10, bottom: 10, left: 10, right: 10)

        // TOP_LEFT: x = safeArea.left + offsets.left, y = safeArea.top + offsets.top
        let topLeft = InAppWindowManager.calculateFrame(
            for: layout(position: .topLeft, offsets: offsets, addSafeAreaInsetsToOffsets: true),
            in: screenBounds,
            safeArea: safeArea
        )
        XCTAssertEqual(topLeft.origin.x, safeArea.left + 10)
        XCTAssertEqual(topLeft.origin.y, safeArea.top + 10)

        // BOTTOM_RIGHT: x = screenWidth - width - (safeArea.right + offsets.right)
        let bottomRight = InAppWindowManager.calculateFrame(
            for: layout(position: .bottomRight, offsets: offsets, addSafeAreaInsetsToOffsets: true),
            in: screenBounds,
            safeArea: safeArea
        )
        XCTAssertEqual(bottomRight.origin.x, screenBounds.width - 300 - (safeArea.right + 10))
        XCTAssertEqual(bottomRight.origin.y, screenBounds.height - 200 - (safeArea.bottom + 10))

        // CENTER: y = (safeArea.top + offsets.top) + (availableHeight - height) / 2
        let center = InAppWindowManager.calculateFrame(
            for: layout(position: .center, offsets: offsets, addSafeAreaInsetsToOffsets: true),
            in: screenBounds,
            safeArea: safeArea
        )
        let marginTop = safeArea.top + 10
        let marginBottom = safeArea.bottom + 10
        let marginLeft = safeArea.left + 10
        let marginRight = safeArea.right + 10
        let availableWidth = screenBounds.width - marginLeft - marginRight
        let availableHeight = screenBounds.height - marginTop - marginBottom
        XCTAssertEqual(center.origin.x, marginLeft + (availableWidth - 300) / 2)
        XCTAssertEqual(center.origin.y, marginTop + (availableHeight - 200) / 2)
    }

    // MARK: - addSafeAreaInsetsToOffsets=false uses offsets as-is

    func testAddSafeAreaInsetsFalseUsesOffsetsAsIs() {
        let offsets = Offsets(top: 10, bottom: 10, left: 10, right: 10)

        let topLeft = InAppWindowManager.calculateFrame(
            for: layout(position: .topLeft, offsets: offsets, addSafeAreaInsetsToOffsets: false),
            in: screenBounds,
            safeArea: safeArea
        )
        XCTAssertEqual(topLeft.origin.x, 10, "safe area must not be added to left offset")
        XCTAssertEqual(topLeft.origin.y, 10, "safe area must not be added to top offset")

        let bottomRight = InAppWindowManager.calculateFrame(
            for: layout(position: .bottomRight, offsets: offsets, addSafeAreaInsetsToOffsets: false),
            in: screenBounds,
            safeArea: safeArea
        )
        XCTAssertEqual(bottomRight.origin.x, screenBounds.width - 300 - 10)
        XCTAssertEqual(bottomRight.origin.y, screenBounds.height - 200 - 10)

        let center = InAppWindowManager.calculateFrame(
            for: layout(position: .center, offsets: offsets, addSafeAreaInsetsToOffsets: false),
            in: screenBounds,
            safeArea: safeArea
        )
        // With safe area skipped, margins are just the offsets.
        let availableWidth = screenBounds.width - 10 - 10
        let availableHeight = screenBounds.height - 10 - 10
        XCTAssertEqual(center.origin.x, 10 + (availableWidth - 300) / 2)
        XCTAssertEqual(center.origin.y, 10 + (availableHeight - 200) / 2)
    }

    func testAddSafeAreaInsetsFalseProducesMoreAvailableSpaceThanTrueWhenSafeAreaIsNonZero() {
        // Use a percent dimension so clamping shows the diff.
        let fullWidth = Dimension(value: 100, unit: .percent)
        let fullHeight = Dimension(value: 100, unit: .percent)
        let offsets = Offsets(top: 5, bottom: 5, left: 5, right: 5)
        // Use a safe area with non-zero insets on all four sides so both width and height diverge.
        let fourSidedSafeArea = UIEdgeInsets(top: 47, left: 20, bottom: 34, right: 20)

        let safeAreaTrue = FormLayout(
            position: .center,
            width: fullWidth,
            height: fullHeight,
            offsets: offsets,
            addSafeAreaInsetsToOffsets: true
        )
        let safeAreaFalse = FormLayout(
            position: .center,
            width: fullWidth,
            height: fullHeight,
            offsets: offsets,
            addSafeAreaInsetsToOffsets: false
        )

        let trueFrame = InAppWindowManager.calculateFrame(
            for: safeAreaTrue, in: screenBounds, safeArea: fourSidedSafeArea
        )
        let falseFrame = InAppWindowManager.calculateFrame(
            for: safeAreaFalse, in: screenBounds, safeArea: fourSidedSafeArea
        )

        XCTAssertGreaterThan(falseFrame.width, trueFrame.width)
        XCTAssertGreaterThan(falseFrame.height, trueFrame.height)
    }

    // MARK: - FULLSCREEN ignores the flag

    func testFullscreenFillsScreenBoundsRegardlessOfFlag() {
        let offsets = Offsets(top: 10, bottom: 10, left: 10, right: 10)

        let withSafeArea = InAppWindowManager.calculateFrame(
            for: layout(position: .fullscreen, offsets: offsets, addSafeAreaInsetsToOffsets: true),
            in: screenBounds,
            safeArea: safeArea
        )
        let withoutSafeArea = InAppWindowManager.calculateFrame(
            for: layout(position: .fullscreen, offsets: offsets, addSafeAreaInsetsToOffsets: false),
            in: screenBounds,
            safeArea: safeArea
        )

        XCTAssertEqual(withSafeArea, screenBounds)
        XCTAssertEqual(withoutSafeArea, screenBounds)
    }
}
