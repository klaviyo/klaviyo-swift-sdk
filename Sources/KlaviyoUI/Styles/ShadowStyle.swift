//
//  ShadowStyle.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/28/24.
//

import UIKit

public struct ShadowStyle {
    let color: CGColor
    let opacity: Float
    let offset: CGSize
    let radius: CGFloat
}

extension ShadowStyle {
    public static var `default`: Self = .init(
        color: UIColor.black.cgColor,
        opacity: 0.5,
        offset: CGSize(width: 5, height: 5),
        radius: 8)
}
