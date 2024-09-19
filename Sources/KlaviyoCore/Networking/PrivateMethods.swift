//
//  PrivateMethods.swift
//
//
//  Created by Ajay Subramanya on 8/29/24.
//

import Foundation

/// Used to override SDK defailts for INTERNAL USE ONLY
/// - Parameter url: The  URL to use for Klaviyo client APIs, This is used internally to test the SDK against different backends, DO NOT use this in your apps.
@_spi(KlaviyoPrivate)
@available(*, deprecated, message: "This function is for internal use only, and should NOT be used in production applications")
public func overrideSDKDefaults(url: String? = nil) {
    if let url = url {
        environment.apiURL = { url }
    }
}
