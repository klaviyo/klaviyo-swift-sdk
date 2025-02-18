//
//  UIApplication+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 12/4/24.
//

import Foundation
import UIKit

extension UIApplication {
    var topMostViewController: UIViewController? {
        guard let keyWindow = getKeyWindow() else { return nil }
        var topController = keyWindow.rootViewController
        while let presentedController = topController?.presentedViewController {
            if let navigationController = presentedController as? UINavigationController {
                topController = navigationController.visibleViewController
            } else if let tabBarController = presentedController as? UITabBarController {
                topController = tabBarController.selectedViewController
            } else {
                topController = presentedController
            }
        }
        return topController
    }

    private func getKeyWindow() -> UIWindow? {
        connectedScenes
            .filter { $0 is UIWindowScene }
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
    }
}
