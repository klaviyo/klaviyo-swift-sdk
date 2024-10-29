//
//  File.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/22/24.
//

import Foundation
import UIKit

public class KlaviyoWebWrapperViewController: UIViewController {
    // MARK: - Properties

    let viewModel: KlaviyoWebViewModeling
    let style: KlaviyoWebWrapperStyle

    private lazy var dismissGestureRecognizer: UITapGestureRecognizer = {
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDismissGesture))
        tapRecognizer.numberOfTapsRequired = 1
        tapRecognizer.numberOfTouchesRequired = 1
        return tapRecognizer
    }()

    // MARK: - Subviews

    private lazy var blurEffectView: UIVisualEffectView? = {
        guard case let .blurred(effect) = style.backgroundStyle else { return nil }

        let blurEffect = UIBlurEffect(style: effect)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)

        blurEffectView.addGestureRecognizer(dismissGestureRecognizer)

        return blurEffectView
    }()

    private lazy var tintView: UIView? = {
        guard case let .tinted(color, opacity) = style.backgroundStyle else { return nil }

        let tintView = UIView()
        tintView.backgroundColor = color
        tintView.layer.opacity = opacity

        tintView.addGestureRecognizer(dismissGestureRecognizer)

        return tintView
    }()

    private lazy var shadowContainerView: UIView? = {
        guard let shadowProperties = style.shadowStyle else { return nil }

        let shadowContainerView = UIView()

        shadowContainerView.layer.shadowColor = shadowProperties.color
        shadowContainerView.layer.shadowOpacity = shadowProperties.opacity
        shadowContainerView.layer.shadowOffset = shadowProperties.offset
        shadowContainerView.layer.shadowRadius = shadowProperties.radius

        shadowContainerView.layer.masksToBounds = false

        return shadowContainerView
    }()

    private lazy var webViewController: KlaviyoWebViewController = {
        let webViewController = KlaviyoWebViewController(viewModel: viewModel)
        guard let webView = webViewController.view else { return webViewController }
        webView.layer.cornerRadius = 16
        webView.layer.masksToBounds = true

        return webViewController
    }()

    // MARK: - View Initialization

    init(viewModel: KlaviyoWebViewModeling, style: KlaviyoWebWrapperStyle = .default) {
        self.viewModel = viewModel
        self.style = style

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        loadSubviews()
    }

    func loadSubviews() {
        if let blurEffectView {
            view.addSubview(blurEffectView)
            blurEffectView.pin(to: view)
        }

        if let tintView {
            view.addSubview(tintView)
            tintView.pin(to: view)
        }

        guard let webView = webViewController.view else { return }
        let webViewInsets = style.insets

        if let shadowContainerView {
            view.addSubview(shadowContainerView)
            shadowContainerView.addSubview(webView)

            shadowContainerView.pin(to: view.safeAreaLayoutGuide, insets: webViewInsets)
            webView.pin(to: shadowContainerView)

            addChild(webViewController)
            webViewController.didMove(toParent: self)
        } else {
            view.addSubview(webView)

            webView.pin(to: view.safeAreaLayoutGuide, insets: webViewInsets)

            addChild(webViewController)
            webViewController.didMove(toParent: self)
        }
    }

    // MARK: - user interactions

    @objc private func handleDismissGesture() {
        viewModel.dismiss()
    }
}

// MARK: - Previews

#if DEBUG
func createKlaviyoWebPreview(url: URL, style: KlaviyoWebWrapperStyle) -> UIViewController {
    let viewModel = KlaviyoWebViewModel(url: url)
    let viewController = KlaviyoWebWrapperViewController(viewModel: viewModel, style: style)

    // Add a dummy view in the background to preview what the KlaviyoWebWrapperViewController
    // might look like when it's displayed on top of a view in an app.
    let childViewController = PreviewTabViewController()
    viewController.view.addSubview(childViewController.view)
    viewController.view.sendSubviewToBack(childViewController.view)
    viewController.addChild(childViewController)
    childViewController.didMove(toParent: viewController)

    return viewController
}
#endif

#if swift(>=5.9)
@available(iOS 17.0, *)
#Preview("Default style") {
    let url = URL(string: "https://www.google.com")!
    return createKlaviyoWebPreview(url: url, style: .default)
}

@available(iOS 17.0, *)
#Preview("Tinted background") {
    let url = URL(string: "https://www.google.com")!
    let style = KlaviyoWebWrapperStyle(
        backgroundStyle: .tinted(opacity: 0.6),
        insets: NSDirectionalEdgeInsets(top: 24, leading: 36, bottom: 24, trailing: 36),
        cornerRadius: 24,
        shadowStyle: .default)

    return createKlaviyoWebPreview(url: url, style: style)
}
#endif
