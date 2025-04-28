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
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.setupLifecycleEvents()
                IAFPresentationManager.shared.presentIAF()
            }
        }
    }

    @MainActor
    @_spi(KlaviyoPrivate)
    @available(*, deprecated, message: "This function is for internal use only, and should not be used in production applications")
    public func registerForInAppForms(assetSource: String) {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.presentIAF(assetSource: assetSource)
            }
        }
    }
}
