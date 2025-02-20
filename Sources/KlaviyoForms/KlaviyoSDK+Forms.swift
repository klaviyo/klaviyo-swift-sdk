//
//  KlaviyoSDK+Forms.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/20/25.
//

import Foundation
import KlaviyoSwift

extension KlaviyoSDK {
    @MainActor
    public func registerForInAppForms() {
        IAFPresentationManager.shared.presentIAF()
    }
}
