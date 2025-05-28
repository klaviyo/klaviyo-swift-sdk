//
//  SDKError.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 5/28/25.
//

package enum SDKError: Error {
    /// The SDK has not been initialized
    case notInitialized

    /// API Key (aka Company ID) is nil or an emtpy string
    case apiKeyNilOrEmpty
}
