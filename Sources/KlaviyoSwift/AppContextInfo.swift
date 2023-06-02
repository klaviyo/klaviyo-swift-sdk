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
private let DEFAULT_APP_NAME: String = info?["CFBundleName"] as? String ?? "Unknown"
private let DEFAULT_OS_VERSION = ProcessInfo.processInfo.operatingSystemVersion
private let DEFAULT_MANUFACTURER = "Apple"
private let DEFAULT_OS_NAME = "iOS"
private let DEFAULT_DEVICE_MODEL: String = {
    var size = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    var machine = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.machine", &machine, &size, nil, 0)
    return String(cString: machine)
}()

struct AppContextInfo {
    let executable: String
    let bundleId: String
    let appVersion: String
    let appBuild: String
    let appName: String
    let version: OperatingSystemVersion
    let osName: String
    let manufacturer: String
    let deviceModel: String

    var osVersion: String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    var osVersionName: String {
        "\(osName) \(osVersion)"
    }

    init(executable: String = DEFAULT_EXECUTABLE,
         bundleId: String = DEFAULT_BUNDLE_ID,
         appVersion: String = DEFAULT_APP_VERSION,
         appBuild: String = DEFAULT_APP_BUILD,
         appName: String = DEFAULT_APP_NAME,
         version: OperatingSystemVersion = DEFAULT_OS_VERSION,
         osName: String = DEFAULT_OS_NAME,
         manufacturer: String = DEFAULT_MANUFACTURER,
         deviceModel: String = DEFAULT_DEVICE_MODEL) {
        self.executable = executable
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.appName = appName
        self.version = version
        self.osName = osName
        self.manufacturer = manufacturer
        self.deviceModel = deviceModel
    }
}
