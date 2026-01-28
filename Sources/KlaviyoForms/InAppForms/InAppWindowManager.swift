//
//  InAppWindowManager.swift
//  klaviyo-swift-sdk
//
//  Created by Auto on 1/22/26.
//

import Foundation
import OSLog
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

        // Get or create a window scene
        if #available(iOS 13.0, *) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            // Prefer the active foreground scene
            windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        }

        // Create the window
        if #available(iOS 13.0, *), let windowScene = windowScene {
            window = UIWindow(windowScene: windowScene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }

        guard let window = window else { return }

        // Configure the window
        window.rootViewController = viewController
        window.backgroundColor = .clear
        window.clipsToBounds = true
        window.isHidden = false
        window.makeKeyAndVisible()

        // Set window level to appear above normal windows but below alerts
        window.windowLevel = .normal + 1

        // Calculate and set frame based on layout
        updateWindowFrame()

        // Set up observers for orientation and keyboard changes
        setupObservers()
    }

    /// Returns true if the window manager has an active window.
    var hasActiveWindow: Bool {
        window != nil && window?.isHidden == false
    }

    /// Dismisses and removes the window.
    func dismiss() {
        removeObservers()
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        windowScene = nil
        currentLayout = nil
    }

    // MARK: - Private Methods

    private func updateWindowFrame() {
        guard let window = window,
              let layout = currentLayout else { return }

        let screenBounds = getScreenBounds()
        if #available(iOS 13.0, *), let windowScene = windowScene {
            window.windowScene = windowScene
        }

        window.frame = calculateFrame(for: layout, in: screenBounds)
    }

    private func getScreenBounds() -> CGRect {
        if #available(iOS 13.0, *), let windowScene = windowScene {
            return windowScene.coordinateSpace.bounds
        } else {
            return UIScreen.main.bounds
        }
    }

    /// Calculates the frame for a given layout within screen bounds.
    private func calculateFrame(for layout: FormLayout, in screenBounds: CGRect) -> CGRect {
        let margin = layout.effectiveMargin
        let screenWidth = screenBounds.width
        let screenHeight = screenBounds.height

        let width = layout.width.toPoints(relativeTo: screenWidth)
        let height = layout.height.toPoints(relativeTo: screenHeight)

        let marginTop = margin.top.toPoints(relativeTo: screenHeight)
        let marginBottom = margin.bottom.toPoints(relativeTo: screenHeight)
        let marginLeft = margin.left.toPoints(relativeTo: screenWidth)
        let marginRight = margin.right.toPoints(relativeTo: screenWidth)

        let origin: CGPoint
        switch layout.position {
        case .fullscreen:
            return screenBounds
        case .top:
            origin = CGPoint(x: marginLeft, y: marginTop)
        case .bottom:
            origin = CGPoint(x: marginLeft, y: screenHeight - height - marginBottom)
        case .topLeft:
            origin = CGPoint(x: marginLeft, y: marginTop)
        case .topRight:
            origin = CGPoint(x: screenWidth - width - marginRight, y: marginTop)
        case .bottomLeft:
            origin = CGPoint(x: marginLeft, y: screenHeight - height - marginBottom)
        case .bottomRight:
            origin = CGPoint(x: screenWidth - width - marginRight, y: screenHeight - height - marginBottom)
        case .center:
            origin = CGPoint(x: (screenWidth - width) / 2, y: (screenHeight - height) / 2)
        }

        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private func setupObservers() {
        // Orientation change
        NotificationCenter.default.addObserver(self, selector: #selector(handleOrientationChange), name: UIDevice.orientationDidChangeNotification, object: nil)

        // Keyboard show/hide
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardChange(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardChange(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleOrientationChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateWindowFrame()
        }
    }

    @objc
    private func handleKeyboardChange(_ notification: Notification) {
        guard let window = window,
              let layout = currentLayout,
              let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        // Only adjust for bottom-anchored forms when keyboard appears
        guard layout.position == .bottom || layout.position == .bottomLeft || layout.position == .bottomRight else {
            return
        }

        var screenBounds = getScreenBounds()

        // Adjust available bounds to account for keyboard
        if notification.name == UIResponder.keyboardWillShowNotification {
            screenBounds.size.height -= keyboardFrame.height
        }

        window.frame = calculateFrame(for: layout, in: screenBounds)
    }
}
