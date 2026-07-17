//
// DebugViewController.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import UIKit

class DebugViewController: UIViewController {
    var debugMessage: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Debug view"
        view.backgroundColor = .systemBackground

        let debugTextView = UITextView()
        debugTextView.font = .preferredFont(forTextStyle: .largeTitle)
        debugTextView.text = debugMessage ?? "no debug message found"
        view.addSubview(debugTextView)

        debugTextView.translatesAutoresizingMaskIntoConstraints = false
        debugTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8).isActive = true
        debugTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8).isActive = true
        debugTextView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        debugTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }
}
