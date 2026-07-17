//
// PrivateMethods.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Foundation

/// Used to override SDK defailts for INTERNAL USE ONLY
/// - Parameter url: The  URL to use for Klaviyo client APIs, This is used internally to test the SDK against different backends, DO NOT use this in your apps.
@_spi(KlaviyoPrivate)
@available(*, deprecated, message: "This function is for internal use only, and should NOT be used in production applications")
public func overrideSDKDefaults(urlComponents: URLComponents? = nil) {
    if let urlComponents {
        environment.apiURL = { urlComponents }

        var cdnURLComponents = urlComponents
        if cdnURLComponents.host == "a.klaviyo.com" {
            cdnURLComponents.host = "static.klaviyo.com"
        }

        environment.cdnURL = { cdnURLComponents }
    }
}
