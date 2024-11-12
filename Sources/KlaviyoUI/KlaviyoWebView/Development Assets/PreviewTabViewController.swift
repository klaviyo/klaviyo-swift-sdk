//
//  PreviewTabViewController.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/23/24.
//

#if DEBUG
import Foundation
import UIKit

/// A sample tab view for internal Xcode preview purposes only.
class PreviewTabViewController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let firstVC = PreviewGridViewController()
        let secondVC = UIViewController()
        let thirdVC = UIViewController()

        firstVC.title = "Browse"

        firstVC.tabBarItem = UITabBarItem(title: "Browse", image: UIImage(systemName: "house"), tag: 0)
        secondVC.tabBarItem = UITabBarItem(title: "Search", image: UIImage(systemName: "magnifyingglass"), tag: 1)
        thirdVC.tabBarItem = UITabBarItem(title: "Profile", image: UIImage(systemName: "person"), tag: 2)

        viewControllers = [
            UINavigationController(rootViewController: firstVC),
            UINavigationController(rootViewController: secondVC),
            UINavigationController(rootViewController: thirdVC)
        ]

        firstVC.navigationController?.navigationBar.prefersLargeTitles = true
    }
}
#endif
