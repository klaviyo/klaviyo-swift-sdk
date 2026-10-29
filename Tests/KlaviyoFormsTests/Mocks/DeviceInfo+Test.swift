//
//  DeviceInfo+Test.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import UIKit

extension DeviceInfo {
    /// A fixed snapshot for tests. Pass it instead of the default `DeviceInfo.current`, whose
    /// `UIScreen.main` fallback in a hostless test process makes UIKit's first-use setup wait
    /// on the simulator's SpringBoard, which can hang the first test that reaches it.
    static let test = DeviceInfo.make(
        screenBounds: CGSize(width: 393, height: 852),
        orientation: .portrait,
        nativeScale: 3,
        safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    )
}
