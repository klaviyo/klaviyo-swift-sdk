//
//  FormLayout.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/22/26.
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

/// Margins from the anchor position, in points.
struct Margins: Codable, Equatable {
    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    let right: CGFloat

    static let zero = Margins(top: 0, bottom: 0, left: 0, right: 0)
}

/// Layout configuration for flexible/banner forms.
struct FormLayout: Codable, Equatable {
    let position: FormPosition
    let width: Dimension
    let height: Dimension
    let margin: Margins

    static let fullDimension = Dimension(value: 100, unit: .percent)

    init(
        position: FormPosition,
        width: Dimension = fullDimension,
        height: Dimension = fullDimension,
        margin: Margins = .zero
    ) {
        self.position = position
        self.width = width
        self.height = height
        self.margin = margin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decode(FormPosition.self, forKey: .position)
        width = try container.decodeIfPresent(Dimension.self, forKey: .width) ?? Self.fullDimension
        height = try container.decodeIfPresent(Dimension.self, forKey: .height) ?? Self.fullDimension
        margin = try container.decodeIfPresent(Margins.self, forKey: .margin) ?? .zero
    }
}
