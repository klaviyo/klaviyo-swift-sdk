//
//  InAppWindowManager.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/22/26.
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

    private init() {}

    /// Presents the view controller in a window configured according to the layout.
    func present(viewController: KlaviyoWebViewController, layout: FormLayout) {
        dismiss()
        currentLayout = layout

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first

        if let windowScene {
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
        if let windowScene {
            return windowScene.coordinateSpace.bounds
        } else {
            return UIScreen.main.bounds
        }
    }

    private func calculateFrame(for layout: FormLayout, in screenBounds: CGRect, keyboardVisible: Bool = false) -> CGRect {
        guard layout.position != .fullscreen else {
            return screenBounds
        }

        // Read safe area insets from the key window to avoid placing the form
        // behind notches, Dynamic Island, or the home indicator.
        let safeArea = windowScene?.windows.first?.safeAreaInsets ?? .zero

        let margin = layout.margin
        let screenWidth = screenBounds.width
        let screenHeight = screenBounds.height

        let width = layout.width.toPoints(relativeTo: screenWidth)
        let height = layout.height.toPoints(relativeTo: screenHeight)

        let marginTop = safeArea.top + margin.top
        let marginBottom = (keyboardVisible ? 0 : safeArea.bottom) + margin.bottom
        let marginLeft = safeArea.left + margin.left
        let marginRight = safeArea.right + margin.right

        let availableWidth = screenWidth - marginLeft - marginRight
        let availableHeight = screenHeight - marginTop - marginBottom
        let clampedWidth = min(width, availableWidth)
        let clampedHeight = min(height, availableHeight)

        let x: CGFloat
        let y: CGFloat

        switch layout.position {
        case .top:
            x = marginLeft + (availableWidth - clampedWidth) / 2
            y = marginTop
        case .topLeft:
            x = marginLeft
            y = marginTop
        case .topRight:
            x = screenWidth - clampedWidth - marginRight
            y = marginTop
        case .bottom:
            x = marginLeft + (availableWidth - clampedWidth) / 2
            y = screenHeight - clampedHeight - marginBottom
        case .bottomLeft:
            x = marginLeft
            y = screenHeight - clampedHeight - marginBottom
        case .bottomRight:
            x = screenWidth - clampedWidth - marginRight
            y = screenHeight - clampedHeight - marginBottom
        case .center:
            x = marginLeft + (availableWidth - clampedWidth) / 2
            y = marginTop + (availableHeight - clampedHeight) / 2
        case .fullscreen:
            return screenBounds
        }

        return CGRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleOrientationChange), name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardChange(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardChange(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc
    private func handleOrientationChange() {
        updateWindowFrame()
    }

    @objc
    private func handleKeyboardChange(_ notification: Notification) {
        guard let window,
              let currentLayout,
              let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              isBottomAnchored(currentLayout.position) else {
            return
        }

        var screenBounds = getScreenBounds()
        let isShowing = notification.name == UIResponder.keyboardWillShowNotification
        if isShowing {
            screenBounds.size.height -= keyboardFrame.height
        }

        window.frame = calculateFrame(for: currentLayout, in: screenBounds, keyboardVisible: isShowing)
    }

    private func isBottomAnchored(_ position: FormPosition) -> Bool {
        position == .bottom || position == .bottomLeft || position == .bottomRight
    }
}
