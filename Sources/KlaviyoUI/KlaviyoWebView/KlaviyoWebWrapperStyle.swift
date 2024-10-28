//
//  KlaviyoWebWrapperStyle.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/28/24.
//

import UIKit

public struct KlaviyoWebWrapperStyle {
    public enum BackgroundStyle {
        case blurred(effect: UIBlurEffect.Style)
        case tinted(color: UIColor = .black, opacity: Float)
    }

    var backgroundStyle: BackgroundStyle
    var insets: NSDirectionalEdgeInsets
    var cornerRadius: CGFloat
    var shadowStyle: ShadowStyle?
}

extension KlaviyoWebWrapperStyle {
    static var `default` = Self(
        backgroundStyle: .blurred(effect: .systemUltraThinMaterialDark),
        insets: NSDirectionalEdgeInsets(top: 24, leading: 36, bottom: 24, trailing: 36),
        cornerRadius: 16.0,
        shadowStyle: .init(
            color: UIColor.black.cgColor,
            opacity: 0.5,
            offset: CGSize(width: 5, height: 5),
            radius: 8))
}
