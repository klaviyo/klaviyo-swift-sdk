//
//  UIView+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/25/24.
//

import UIKit

extension UIView {
    /// Pins the view to the edges of the parent view.
    /// - Parameter parentView: The parent view to pin this view to.
    func pin(to parentView: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            topAnchor.constraint(equalTo: parentView.topAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
    }

    /// Pins the view to the edges of the given safe area with optional insets.
    /// - Parameters:
    ///   - safeArea: The UILayoutGuide (usually `view.safeAreaLayoutGuide`) to pin the view to.
    ///   - insets: Optional insets for each side, default is `.zero`.
    func pin(to safeArea: UILayoutGuide, insets: NSDirectionalEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: safeArea.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: insets.leading),
            bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -insets.bottom),
            trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -insets.trailing)
        ])
    }
}
