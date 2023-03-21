//
//  AppContextInfo.swift
//
//
//  Created by Noah Durell on 11/18/22.
//
import Foundation

private let info = Bundle.main.infoDictionary
private let DEFAULT_EXECUTABLE: String = (info?["CFBundleExecutable"] as? String) ??
    (ProcessInfo.processInfo.arguments.first?.split(separator: "/").last.map(String.init)) ?? "Unknown"
private let DEFAULT_BUNDLE_ID: String = info?["CFBundleIdentifier"] as? String ?? "Unknown"
private let DEFAULT_APP_VERSION: String = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
private let DEFAULT_APP_BUILD: String = info?["CFBundleVersion"] as? String ?? "Unknown"
private let DEFAULT_OS_VERSION = ProcessInfo.processInfo.operatingSystemVersion
private let DEFAULT_OS_NAME = "iOS"

struct AppContextInfo {
    let excutable: String
    let bundleId: String
    let appVersion: String
    let appBuild: String
    let version: OperatingSystemVersion
    let osName: String
    var osVersion: String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    var osVersionName: String {
        "\(osName) \(osVersion)"
    }

    init(excutable: String = DEFAULT_EXECUTABLE,
         bundleId: String = DEFAULT_BUNDLE_ID,
         appVersion: String = DEFAULT_APP_VERSION,
         appBuild: String = DEFAULT_APP_BUILD,
         version: OperatingSystemVersion = DEFAULT_OS_VERSION,
         osName: String = DEFAULT_OS_NAME) {
        self.excutable = excutable
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.version = version
        self.osName = osName
    }
}
