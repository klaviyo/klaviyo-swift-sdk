//
//  IAFPresenter.swift
//  klaviyo-swift-sdk
//

import Foundation
import OSLog
import UIKit

/// Puts a form on screen and takes it off again.
///
/// Pure UIKit: knows nothing about API keys, sessions, handshakes, or JavaScript. Given a
/// view controller and a layout it decides between the window-manager path (flexible forms)
/// and modal presentation (fullscreen), and handles the one awkward case where an alert is
/// already up.
@MainActor
final class IAFPresenter {
    /// Retry timer used when presentation is blocked by a `UIAlertController`.
    private var delayedPresentationTask: Task<Void, Never>?

    init() {}

    deinit {
        // `deinit` is nonisolated; the task is safe to cancel from any context.
        delayedPresentationTask?.cancel()
    }

    func present(_ viewController: KlaviyoWebViewController, layout: FormLayout?) {
        if let layout, layout.position != .fullscreen {
            // Flexible form: use window manager
            cancelDelayedPresentation()
            InAppWindowManager.shared.present(viewController: viewController, layout: layout)
        } else {
            // Fullscreen form: use modal presentation
            presentAsModal(viewController)
        }
    }

    func dismiss(_ viewController: KlaviyoWebViewController) {
        if InAppWindowManager.shared.hasActiveWindow {
            // Flexible form: dismiss window
            InAppWindowManager.shared.dismiss()
        } else {
            // Fullscreen form: dismiss modal
            viewController.dismiss(animated: false, completion: nil)
        }
    }

    func cancelDelayedPresentation() {
        delayedPresentationTask?.cancel()
        delayedPresentationTask = nil
    }

    // MARK: - Modal presentation

    private func presentAsModal(_ viewController: KlaviyoWebViewController) {
        guard let topController = UIApplication.shared.topMostViewController else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning(
                    "Unable to access topMostViewController; ignoring `presentForm()` request."
                )
            }
            return
        }

        if topController is UIAlertController {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning(
                    "Alert is currently being displayed. Delaying form presentation until alert is dismissed."
                )
            }

            // Retry after a short delay. Cancel any in-flight delayed task before starting a new one.
            delayedPresentationTask?.cancel()
            delayedPresentationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self?.presentAsModal(viewController)
            }
        } else {
            if topController.isKlaviyoVC || topController.hasKlaviyoVCInStack {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("In-App Form is already being presented; ignoring request")
                }
            } else {
                topController.present(viewController, animated: false, completion: nil)
            }
        }
    }
}

// MARK: - UI helpers

extension UIViewController {
    fileprivate var isKlaviyoVC: Bool {
        self is KlaviyoWebViewController
    }

    fileprivate var hasKlaviyoVCInStack: Bool {
        guard let navigationController else {
            return false
        }
        return navigationController.viewControllers.contains(where: \.isKlaviyoVC)
    }
}
