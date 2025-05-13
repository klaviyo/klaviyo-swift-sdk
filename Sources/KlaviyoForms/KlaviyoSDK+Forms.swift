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
    public func registerForInAppForms(configuration: IAFConfiguration = IAFConfiguration()) {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.setupLifecycleEvents(configuration: configuration)
                IAFPresentationManager.shared.constructWebview()
            }
        }
    }

    @MainActor
    @_spi(KlaviyoPrivate)
    @available(*, deprecated, message: "This function is for internal use only, and should not be used in production applications")
    public func registerForInAppForms(configuration: IAFConfiguration = IAFConfiguration(), assetSource: String) {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.setupLifecycleEvents(configuration: configuration)
                IAFPresentationManager.shared.constructWebview(assetSource: assetSource)
            }
        }
    }
}
