//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/29/24.
//

import Foundation

@_spi(KlaviyoPrivate)
/// Used to override the URL that the SDK will interface for network activity
/// This is used internally to test the SDK against different backends, DO NOT use this in your apps.
/// - Parameter url: the backing url to use for setting API
public func setKlaviyoAPIURL(url: String) {
    environment.apiURL = url
}

@_spi(KlaviyoPrivate)
/// Used to set the SDK name and version.
/// This is mainly used by Klaviyo's react native SDK to override native platform values
/// DO NOT overrrifde this in yout apps as it will lead to network errors as our backend will not accept unsupported values here and your network requests will fail.
/// - Parameters:
///   - name: The name of the SDK
///   - version: The version of the SDK
public func setKlaviyoSDKNameAndVersion(name: String, version: String) {
    environment.SDKName = name
    environment.SDKVersion = version
}
