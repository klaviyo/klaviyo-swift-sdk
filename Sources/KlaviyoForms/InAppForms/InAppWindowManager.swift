//
//  InAppWindowManager.swift
//  klaviyo-swift-sdk
//
//  Created by Auto on 1/22/26.
//

import Foundation
import UIKit

/// Manages the UIWindow lifecycle for flexible/banner in-app forms.
@MainActor
class InAppWindowManager {
    static let shared = InAppWindowManager()

    private var window: UIWindow?
    private var windowScene: UIWindowScene?
    private var currentLayout: FormLayout?
    private weak var presentedViewController: KlaviyoWebViewController?

    private init() {}

    /// Presents the view controller in a window configured according to the layout.
    func present(viewController: KlaviyoWebViewController, layout: FormLayout) {
        dismiss()
        currentLayout = layout

        if #available(iOS 13.0, *) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        }

        if #available(iOS 13.0, *), let windowScene {
            window = UIWindow(windowScene: windowScene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }

        guard let window else { return }
        window.rootViewController = viewController
        window.backgroundColor = .clear
        window.clipsToBounds = true
        window.windowLevel = .normal + 1
        window.isHidden = false
        window.makeKeyAndVisible()

        presentedViewController = viewController
        viewController.onSizeTransition = { [weak self] coordinator in
            coordinator.animate(alongsideTransition: { [weak self] _ in
                self?.updateWindowFrame()
            })
        }

        updateWindowFrame()
        setupObservers()
    }

    /// Returns true if the window manager has an active window.
    var hasActiveWindow: Bool {
        window?.isHidden == false
    }

    /// Dismisses and removes the window.
    func dismiss() {
        NotificationCenter.default.removeObserver(self)
        presentedViewController?.onSizeTransition = nil
        presentedViewController = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        windowScene = nil
        currentLayout = nil
    }

    // MARK: - Private Methods

    private func updateWindowFrame() {
        guard let window, let currentLayout else { return }
        window.frame = calculateFrame(for: currentLayout, in: getScreenBounds())
    }

    private func getScreenBounds() -> CGRect {
        if #available(iOS 13.0, *), let windowScene {
            return windowScene.coordinateSpace.bounds
        } else {
            return UIScreen.main.bounds
        }
    }

    private func calculateFrame(for layout: FormLayout, in screenBounds: CGRect) -> CGRect {
        guard layout.position != .fullscreen else {
            return screenBounds
        }

        let margin = layout.effectiveMargin
        let screenWidth = screenBounds.width
        let screenHeight = screenBounds.height

        let width = layout.effectiveWidth.toPoints(relativeTo: screenWidth)
        let height = layout.effectiveHeight.toPoints(relativeTo: screenHeight)

        let marginTop = CGFloat(margin.top)
        let marginBottom = CGFloat(margin.bottom)
        let marginLeft = CGFloat(margin.left)
        let marginRight = CGFloat(margin.right)

        let x: CGFloat
        let y: CGFloat

        switch layout.position {
        case .top, .topLeft:
            x = marginLeft
            y = marginTop
        case .topRight:
            x = screenWidth - width - marginRight
            y = marginTop
        case .bottom, .bottomLeft:
            x = marginLeft
            y = screenHeight - height - marginBottom
        case .bottomRight:
            x = screenWidth - width - marginRight
            y = screenHeight - height - marginBottom
        case .center:
            x = (screenWidth - width) / 2
            y = (screenHeight - height) / 2
        case .fullscreen:
            return screenBounds
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func setupObservers() {
        // Orientation is handled via viewWillTransition(to:with:) on the presented VC,
        // which provides the correct incoming size and a transition coordinator for animation.
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardChange(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardChange(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc
    private func handleKeyboardChange(_ notification: Notification) {
        guard let window,
              let currentLayout,
              let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }

        let screenBounds = getScreenBounds()
        let isShowing = notification.name == UIResponder.keyboardWillShowNotification
        let keyboardHeight = isShowing ? keyboardFrame.height : 0

        let formHeight = currentLayout.effectiveHeight.toPoints(relativeTo: screenBounds.height)
        let gap = formBottomEdgeGap(for: currentLayout, formHeight: formHeight, in: screenBounds)
        let overlap = max(0, keyboardHeight - gap)

        let newFrame = calculateFrame(for: currentLayout, in: screenBounds).offsetBy(dx: 0, dy: -overlap)

        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [UIView.AnimationOptions(rawValue: curveRaw << 16), .beginFromCurrentState]
        ) {
            window.frame = newFrame
        }
    }

    /// Returns the gap in points between the form's bottom edge and the screen bottom.
    /// Used to calculate how much the keyboard actually overlaps the form.
    private func formBottomEdgeGap(for layout: FormLayout, formHeight: CGFloat, in screenBounds: CGRect) -> CGFloat {
        let margin = layout.effectiveMargin
        let screenHeight = screenBounds.height
        switch layout.position {
        case .bottom, .bottomLeft, .bottomRight:
            return CGFloat(margin.bottom)
        case .top, .topLeft, .topRight:
            return screenHeight - CGFloat(margin.top) - formHeight
        case .center:
            return (screenHeight - formHeight) / 2
        case .fullscreen:
            return 0
        }
    }
}
