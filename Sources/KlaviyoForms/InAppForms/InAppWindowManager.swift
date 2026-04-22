//
//  InAppWindowManager.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/22/26.
//

import UIKit

/// Manages the UIWindow lifecycle for flexible/banner in-app forms.
@MainActor
class InAppWindowManager {
    static let shared = InAppWindowManager()

    private var window: UIWindow?
    private var windowScene: UIWindowScene?
    private var currentLayout: FormLayout?

    /// Tracks the most-recently-reported keyboard end frame so that layout
    /// is keyboard-aware even when a form is presented while the keyboard is
    /// already visible (no new keyboardWillShow fires in that case).
    private var currentKeyboardFrame: CGRect = .zero

    private init() {
        let keyboardEvents: [Notification.Name] = [
            UIResponder.keyboardWillShowNotification,
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardWillHideNotification
        ]
        for keyboardEvent in keyboardEvents {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleKeyboardChange(_:)),
                name: keyboardEvent,
                object: nil
            )
        }
    }

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
        updateWindowFrame()

        viewController.onSizeTransition = { [weak self] _, coordinator in
            coordinator.animate(alongsideTransition: { _ in
                self?.updateWindowFrame()
            }, completion: nil)
        }
    }

    /// Returns true if the window manager has an active window.
    var hasActiveWindow: Bool {
        window?.isHidden == false
    }

    /// Dismisses and removes the window.
    func dismiss() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        windowScene = nil
        currentLayout = nil
    }

    // MARK: - Private Methods

    private func updateWindowFrame() {
        guard let window, let currentLayout else { return }
        let screenBounds = getScreenBounds()
        var frame = calculateFrame(for: currentLayout, in: screenBounds)

        // Shift the frame up to avoid keyboard overlap. Form dimensions are
        // always calculated against full screen bounds so percentage-based sizes
        // aren't affected; we only adjust origin (and height as a last resort).
        if currentLayout.position != .fullscreen, currentKeyboardFrame != .zero {
            let keyboardTop = max(0, currentKeyboardFrame.origin.y)
            let overlap = max(0, frame.maxY - keyboardTop)
            if overlap > 0 {
                let safeAreaTop = windowScene?.windows.first?.safeAreaInsets.top ?? 0
                frame.origin.y = max(safeAreaTop, frame.origin.y - overlap)
                // Only clamp height if the form is taller than the space above the keyboard.
                let remainingOverlap = max(0, frame.maxY - keyboardTop)
                if remainingOverlap > 0 {
                    frame.size.height -= remainingOverlap
                }
            }
        }

        window.frame = frame
    }

    private func getScreenBounds() -> CGRect {
        if let windowScene {
            return windowScene.coordinateSpace.bounds
        } else {
            return UIScreen.main.bounds
        }
    }

    private func calculateFrame(for layout: FormLayout, in screenBounds: CGRect) -> CGRect {
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
        let marginBottom = safeArea.bottom + margin.bottom
        let marginLeft = safeArea.left + margin.left
        let marginRight = safeArea.right + margin.right

        let availableWidth = max(0, screenWidth - marginLeft - marginRight)
        let availableHeight = max(0, screenHeight - marginTop - marginBottom)
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

    @objc
    private func handleKeyboardChange(_ notification: Notification) {
        currentKeyboardFrame = notification.name == UIResponder.keyboardWillHideNotification
            ? .zero
            : (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero)
        updateWindowFrame()
    }
}
