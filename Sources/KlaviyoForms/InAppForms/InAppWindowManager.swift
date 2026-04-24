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

    /// Exposes the form's overlay window so callers that enumerate scene windows can
    /// filter it out — e.g. `DeviceInfo.current()` must not read bounds/insets from
    /// our own overlay (which becomes key while the user interacts with the form).
    var currentFormWindow: UIWindow? { window }

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
        // Read safe area insets from the key window to avoid placing the form
        // behind notches, Dynamic Island, or the home indicator.
        let safeArea = windowScene?.windows.first?.safeAreaInsets ?? .zero
        return Self.calculateFrame(for: layout, in: screenBounds, safeArea: safeArea)
    }

    /// Pure layout computation, extracted for testability.
    nonisolated static func calculateFrame(
        for layout: FormLayout,
        in screenBounds: CGRect,
        safeArea: UIEdgeInsets
    ) -> CGRect {
        guard layout.position != .fullscreen else {
            return screenBounds
        }

        let offsets = layout.offsets
        let screenWidth = screenBounds.width
        let screenHeight = screenBounds.height

        let width = layout.width.toPoints(relativeTo: screenWidth)
        let height = layout.height.toPoints(relativeTo: screenHeight)

        // When `addSafeAreaInsetsToOffsets` is false, onsite has already baked safe-area handling
        // into the provided offsets and the SDK should not add insets of its own.
        let effectiveSafeArea: UIEdgeInsets = layout.addSafeAreaInsetsToOffsets ? safeArea : .zero

        let offsetTop = effectiveSafeArea.top + offsets.top
        let offsetBottom = effectiveSafeArea.bottom + offsets.bottom
        let offsetLeft = effectiveSafeArea.left + offsets.left
        let offsetRight = effectiveSafeArea.right + offsets.right

        let availableWidth = max(0, screenWidth - offsetLeft - offsetRight)
        let availableHeight = max(0, screenHeight - offsetTop - offsetBottom)
        let clampedWidth = min(width, availableWidth)
        let clampedHeight = min(height, availableHeight)

        let x: CGFloat
        let y: CGFloat

        switch layout.position {
        case .top:
            x = offsetLeft + (availableWidth - clampedWidth) / 2
            y = offsetTop
        case .topLeft:
            x = offsetLeft
            y = offsetTop
        case .topRight:
            x = screenWidth - clampedWidth - offsetRight
            y = offsetTop
        case .bottom:
            x = offsetLeft + (availableWidth - clampedWidth) / 2
            y = screenHeight - clampedHeight - offsetBottom
        case .bottomLeft:
            x = offsetLeft
            y = screenHeight - clampedHeight - offsetBottom
        case .bottomRight:
            x = screenWidth - clampedWidth - offsetRight
            y = screenHeight - clampedHeight - offsetBottom
        case .center:
            x = offsetLeft + (availableWidth - clampedWidth) / 2
            y = offsetTop + (availableHeight - clampedHeight) / 2
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
