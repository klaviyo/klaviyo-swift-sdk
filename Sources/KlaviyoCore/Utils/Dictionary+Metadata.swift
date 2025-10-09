//
//  Dictionary+Metadata.swift
//  klaviyo-swift-sdk
//
//  Created by Ajay Subramanya on 10/9/25.
//

import Foundation

extension Dictionary where Key == String, Value == Any {
    /// Appends device, SDK, and app metadata to event properties
    /// - Parameter pushToken: Optional push token to include in metadata
    /// - Returns: Dictionary with metadata merged into properties
    package func appendMetadataToProperties(pushToken: String?) -> [String: Any]? {
        let context = environment.appContextInfo()
        let metadata: [String: Any] = [
            "Device ID": context.deviceId,
            "Device Manufacturer": context.manufacturer,
            "Device Model": context.deviceModel,
            "OS Name": context.osName,
            "OS Version": context.osVersion,
            "SDK Name": environment.sdkName(),
            "SDK Version": environment.sdkVersion(),
            "App Name": context.appName,
            "App ID": context.bundleId,
            "App Version": context.appVersion,
            "App Build": context.appBuild,
            "Push Token": pushToken ?? ""
        ]

        return merging(metadata) { _, new in new }
    }
}
