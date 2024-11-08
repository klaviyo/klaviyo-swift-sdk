//
//  KlaviyoWebWrapperStyle.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/28/24.
//

import SwiftUI
import UIKit

public struct KlaviyoWebWrapperStyle {
    public enum BackgroundStyle {
        case blurred(effect: UIBlurEffect.Style)
        case tinted(color: UIColor = .black, opacity: Float)
    }

    var backgroundStyle: BackgroundStyle
    // FIXME: should this not be optional?
    // FIXME: should I rename this `constraints`? or `edgeConstraints`? or `padding`?
    var insets: [EdgeInset]?
    var cornerRadius: CGFloat
    var shadowStyle: ShadowStyle?
}

extension KlaviyoWebWrapperStyle {
    static var `default` = Self(
        backgroundStyle: .blurred(effect: .systemUltraThinMaterialDark),
        insets: [.horizontal(constant: 36), .vertical(constant: 24)],
        cornerRadius: 16.0,
        shadowStyle: .init(
            color: UIColor.black.cgColor,
            opacity: 0.5,
            offset: CGSize(width: 5, height: 5),
            radius: 8))
}
