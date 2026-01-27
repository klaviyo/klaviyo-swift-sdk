//
//  FormLayout.swift
//  klaviyo-swift-sdk
//
//  Created by Auto on 1/22/26.
//

import Foundation
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
struct Dimension: Codable {
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

/// Margins from the anchor position.
struct Margins: Codable {
    let top: Dimension
    let bottom: Dimension
    let left: Dimension
    let right: Dimension

    static let zero = Margins(
        top: Dimension(value: 0, unit: .fixed),
        bottom: Dimension(value: 0, unit: .fixed),
        left: Dimension(value: 0, unit: .fixed),
        right: Dimension(value: 0, unit: .fixed)
    )
}

/// Layout configuration for flexible/banner forms.
struct FormLayout: Codable {
    let position: FormPosition
    let width: Dimension
    let height: Dimension
    let margin: Margins?

    var effectiveMargin: Margins {
        margin ?? .zero
    }
}
