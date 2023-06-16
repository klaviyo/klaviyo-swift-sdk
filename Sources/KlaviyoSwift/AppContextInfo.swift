//
//  AppContextInfo.swift
//
//
//  Created by Noah Durell on 11/18/22.
//
import Foundation
import UIKit

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

private let DEVICE_ID_STORE_KEY = "_klaviyo_device_id"

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
    let deviceId: String
    let environment: String

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
         deviceModel: String = DEFAULT_DEVICE_MODEL,
         deviceId: String = UIDevice.current.identifierForVendor?.uuidString ?? "") {
        self.executable = executable
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.appName = appName
        self.version = version
        self.osName = osName
        self.manufacturer = manufacturer
        self.deviceModel = deviceModel
        self.deviceId = deviceId

        switch UIDevice.current.pushEnvironment {
        case .development:
            environment = "debug"
        case .production:
            environment = "release"
        case .unknown:
            #if DEBUG
            environment = "debug"
            #else
            environment = "release"
            #endif
        }
    }
}

extension UIDevice {
    public enum PushEnvironment: String {
        case unknown
        case development
        case production
    }

    public var pushEnvironment: PushEnvironment {
        guard let provisioningProfile = try? provisioningProfile(),
              let entitlements = provisioningProfile["Entitlements"] as? [String: Any],
              let environment = entitlements["aps-environment"] as? String
        else {
            return .unknown
        }

        return PushEnvironment(rawValue: environment) ?? .unknown
    }

    // MARK: - Private

    private func provisioningProfile() throws -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return nil
        }

        let binaryString = try String(contentsOf: url, encoding: .isoLatin1)

        let scanner = Scanner(string: binaryString)
        guard scanner.scanUpToString("<plist") != nil, let plistString = scanner.scanUpToString("</plist>"),
              let data = (plistString + "</plist>").data(using: .isoLatin1)
        else {
            return nil
        }

        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }
}
