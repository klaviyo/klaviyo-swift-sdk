//
//  KlaviyoSDK+Location.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/27/25.
//

import Foundation
import KlaviyoSwift

extension KlaviyoSDK {
    @MainActor
    public func registerForGeofences() {
        Task {
            await MainActor.run {
                KlaviyoLocationManager.shared.requestLocationAuthorization()
            }
        }
    }
}
