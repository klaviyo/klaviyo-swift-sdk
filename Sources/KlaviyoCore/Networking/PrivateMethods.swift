//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/29/24.
//

import Foundation

/// Used to override SDK defailts for INTERNAL USE ONLY
/// - Parameter url: The  URL to use for Klaviyo client APIs, This is used internally to test the SDK against different backends, DO NOT use this in your apps.
/// - Parameter name: The name of the SDK, defaults to swift but react native will pass it's own name. DO NOT override this in your apps as our backend will not accept unsupported values here and your network requests will fail.
/// - Parameter version: The version of the swift SDK default to hard coded values here but react native will pass it's own values here. DO NOT override this in your apps.
@_spi(KlaviyoPrivate)
@available(*, deprecated, message: "This function is for internal use only, and should NOT be used in production applications")
public func overrideSDKDefaults(url: String? = nil, name: String? = nil, version: String? = nil) {
    if let url = url {
        environment.apiURL = { url }
    }

    if let name = name {
        environment.sdkName = { name }
    }

    if let version = version {
        environment.sdkVersion = { version }
    }
}
