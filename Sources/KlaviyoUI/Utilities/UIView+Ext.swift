//
//  UIView+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/25/24.
//

import SwiftUI
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

    func pin(to safeArea: UILayoutGuide, edges: [EdgeInset]) {
        translatesAutoresizingMaskIntoConstraints = false

        var topConstraint: NSLayoutConstraint? {
            guard let edge = edges.last(where: { $0.containsTop }) else { return nil }
            return generateConstraint(for: topAnchor, equalTo: safeArea.topAnchor, constant: edge.constant)
        }

        var leadingConstraint: NSLayoutConstraint? {
            guard let edge = edges.last(where: { $0.containsLeading }) else { return nil }
            return generateConstraint(for: leadingAnchor, equalTo: safeArea.leadingAnchor, constant: edge.constant)
        }

        var bottomConstraint: NSLayoutConstraint? {
            guard let edge = edges.last(where: { $0.containsBottom }) else { return nil }
            let constant = edge.constant != nil ? -edge.constant! : nil
            return generateConstraint(for: bottomAnchor, equalTo: safeArea.bottomAnchor, constant: constant)
        }

        var trailingConstraint: NSLayoutConstraint? {
            guard let edge = edges.last(where: { $0.containsTrailing }) else { return nil }
            let constant = edge.constant != nil ? -edge.constant! : nil
            return generateConstraint(for: trailingAnchor, equalTo: safeArea.trailingAnchor, constant: constant)
        }

        let constraints = [
            topConstraint,
            leadingConstraint,
            bottomConstraint,
            trailingConstraint
        ].compactMap { $0 }

        NSLayoutConstraint.activate(constraints)
    }
}

private func generateConstraint<T>(for from: NSLayoutAnchor<T>, equalTo: NSLayoutAnchor<T>, constant: CGFloat? = nil) -> NSLayoutConstraint {
    if let constant {
        from.constraint(equalTo: equalTo, constant: constant)
    } else {
        from.constraint(equalTo: equalTo)
    }
}
