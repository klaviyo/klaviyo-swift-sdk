//
//  FormLayout.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/22/26.
//

import Foundation
import OSLog
import UIKit

/// Position where the form should be anchored on screen.
enum FormPosition: String, Codable {
    case fullscreen = "FULLSCREEN"
    case center = "CENTER"
    case top = "TOP"
    case bottom = "BOTTOM"
    case topLeft = "TOP_LEFT"
    case topRight = "TOP_RIGHT"
    case bottomLeft = "BOTTOM_LEFT"
    case bottomRight = "BOTTOM_RIGHT"
}

/// Unit of measurement for dimensions.
enum DimensionUnit: String, Codable {
    case percent = "PERCENT"
    case fixed = "FIXED"
}

/// A dimension with a value and unit.
struct Dimension: Codable, Equatable {
    let value: Double
    let unit: DimensionUnit

    /// Converts the dimension to points relative to a screen dimension.
    func toPoints(relativeTo screenDimension: CGFloat) -> CGFloat {
        switch unit {
        case .percent:
            return screenDimension * CGFloat(value) / 100.0
        case .fixed:
            return CGFloat(value)
        }
    }
}

/// Offsets from the anchor position, in points.
struct Offsets: Codable, Equatable {
    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    let right: CGFloat

    static let zero = Offsets(top: 0, bottom: 0, left: 0, right: 0)
}

/// Tracks whether we've already logged the `margin` → `offsets` fallback deprecation for this session.
private enum FormLayoutDeprecationLogger {
    private static let hasLoggedMarginFallback = Atomic(false)

    static func logMarginFallbackOnce() {
        guard hasLoggedMarginFallback.compareAndSet(expected: false, newValue: true) else { return }
        if #available(iOS 14.0, *) {
            let message =
                "formWillAppear payload used deprecated `margin` key; prefer `offsets`. " +
                "This warning is logged once per session."
            Logger.webViewLogger.info("\(message)")
        }
    }

    static func resetForTesting() {
        hasLoggedMarginFallback.set(false)
    }
}

/// Minimal atomic Bool wrapper to gate the one-shot deprecation log.
private final class Atomic {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) { self.value = value }

    func set(_ newValue: Bool) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }

    func compareAndSet(expected: Bool, newValue: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard value == expected else { return false }
        value = newValue
        return true
    }
}

/// Layout configuration for flexible/banner forms.
struct FormLayout: Codable, Equatable {
    let position: FormPosition
    let width: Dimension
    let height: Dimension
    let offsets: Offsets
    /// When `true` (default), the SDK adds the window's safe-area insets on top of `offsets`
    /// when positioning the form. When `false`, `offsets` are used as-is — the onsite/web layer
    /// is responsible for accounting for safe-area.
    let addSafeAreaInsetsToOffsets: Bool

    static let fullDimension = Dimension(value: 100, unit: .percent)

    enum CodingKeys: String, CodingKey {
        case position
        case width
        case height
        case offsets
        case margin
        case addSafeAreaInsetsToOffsets
    }

    init(
        position: FormPosition,
        width: Dimension = fullDimension,
        height: Dimension = fullDimension,
        offsets: Offsets = .zero,
        addSafeAreaInsetsToOffsets: Bool = true
    ) {
        self.position = position
        self.width = width
        self.height = height
        self.offsets = offsets
        self.addSafeAreaInsetsToOffsets = addSafeAreaInsetsToOffsets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decode(FormPosition.self, forKey: .position)
        width = try container.decodeIfPresent(Dimension.self, forKey: .width) ?? Self.fullDimension
        height = try container.decodeIfPresent(Dimension.self, forKey: .height) ?? Self.fullDimension

        if let decodedOffsets = try container.decodeIfPresent(Offsets.self, forKey: .offsets) {
            offsets = decodedOffsets
        } else if let legacyMargin = try container.decodeIfPresent(Offsets.self, forKey: .margin) {
            FormLayoutDeprecationLogger.logMarginFallbackOnce()
            offsets = legacyMargin
        } else {
            offsets = .zero
        }

        addSafeAreaInsetsToOffsets = try container
            .decodeIfPresent(Bool.self, forKey: .addSafeAreaInsetsToOffsets) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position, forKey: .position)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(offsets, forKey: .offsets)
        try container.encode(addSafeAreaInsetsToOffsets, forKey: .addSafeAreaInsetsToOffsets)
    }
}

#if DEBUG
enum FormLayoutTestHooks {
    static func resetDeprecationLogger() {
        FormLayoutDeprecationLogger.resetForTesting()
    }
}
#endif
