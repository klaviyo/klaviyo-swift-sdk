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

        // Set window level to appear above normal windows but below alerts
        window.windowLevel = .normal + 1

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

        let width = layout.width.toPoints(relativeTo: screenWidth)
        let height = layout.height.toPoints(relativeTo: screenHeight)

        let marginTop = margin.top.toPoints(relativeTo: screenHeight)
        let marginBottom = margin.bottom.toPoints(relativeTo: screenHeight)
        let marginLeft = margin.left.toPoints(relativeTo: screenWidth)
        let marginRight = margin.right.toPoints(relativeTo: screenWidth)

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
        NotificationCenter.default.addObserver(self, selector: #selector(handleOrientationChange), name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardChange(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardChange(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc
    private func handleOrientationChange() {
        DispatchQueue.main.async { [self] in
            updateWindowFrame()
        }
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
        if notification.name == UIResponder.keyboardWillShowNotification {
            screenBounds.size.height -= keyboardFrame.height
        }

        window.frame = calculateFrame(for: currentLayout, in: screenBounds)
    }

    private func isBottomAnchored(_ position: FormPosition) -> Bool {
        position == .bottom || position == .bottomLeft || position == .bottomRight
    }
}
