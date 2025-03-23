//
//  AppContextInfo.swift
//
//
//  Created by Noah Durell on 11/18/22.
//
import Foundation
import UIKit

private let _defaultAppContextInfo: AppContextInfo? = nil

@MainActor
public func getDefaultAppContextInfo() -> AppContextInfo {
    if let appContextInfo = _defaultAppContextInfo {
        return appContextInfo
    }
    let info = Bundle.main.infoDictionary
    let defaultExecutable: String = (info?["CFBundleExecutable"] as? String) ??
        (ProcessInfo.processInfo.arguments.first?.split(separator: "/").last.map(String.init)) ?? "Unknown"
    let defaultBundleId: String = info?["CFBundleIdentifier"] as? String ?? "Unknown"
    let defaultAppVersion: String = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let defaultAppBuild: String = info?["CFBundleVersion"] as? String ?? "Unknown"
    let defaultAppName: String = info?["CFBundleName"] as? String ?? "Unknown"
    let defaultOSVersion = ProcessInfo.processInfo.operatingSystemVersion
    let defaultManufacturer = "Apple"
    let defaultOSName = "iOS"
    let defaultDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
    let defaultDeviceModel: String = {
        var size = 0
        var deviceModel = ""
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        if size > 0 {
            var machine = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.machine", &machine, &size, nil, 0)
            deviceModel = String(cString: machine)
        }
        return deviceModel
    }()

    let defaultKlaviyoSdk = {
        let plist = loadPlist(named: "klaviyo-sdk-configuration") ?? [:]
        if let sdkName = plist["klaviyo_sdk_name"] as? String {
            return sdkName
        }
        return __klaviyoSwiftName
    }()

    let defaultSdkVersion = {
        let plist = loadPlist(named: "klaviyo-sdk-configuration") ?? [:]
        if let sdkVersion = plist["klaviyo_sdk_version"] as? String {
            return sdkVersion
        }
        return __klaviyoSwiftVersion
    }()

    let defaultEnvironment = UIDevice.current.pushEnvironment.value

    return AppContextInfo(executable: defaultExecutable, bundleId: defaultBundleId, appVersion: defaultAppVersion, appBuild: defaultAppBuild, appName: defaultAppName, version: defaultOSVersion, osName: defaultOSName, manufacturer: defaultManufacturer, deviceModel: defaultDeviceModel, deviceId: defaultDeviceId, environment: defaultEnvironment, klaviyoSdk: defaultKlaviyoSdk, sdkVersion: defaultSdkVersion)
}

public struct AppContextInfo: Sendable, Equatable {
    let executable: String
    let bundleId: String
    let appVersion: String
    let appBuild: String
    let appName: String
    let version: OSVersion
    let osName: String
    let manufacturer: String
    let deviceModel: String
    let deviceId: String
    let environment: String
    public let klaviyoSdk: String
    public let sdkVersion: String

    var osVersion: String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    struct OSVersion: Equatable {
        let majorVersion: Int
        let minorVersion: Int
        let patchVersion: Int
    }

    var osVersionName: String {
        "\(osName) \(osVersion)"
    }

    public init(executable: String,
                bundleId: String,
                appVersion: String,
                appBuild: String,
                appName: String,
                version: OperatingSystemVersion,
                osName: String,
                manufacturer: String,
                deviceModel: String,
                deviceId: String,
                environment: String,
                klaviyoSdk: String,
                sdkVersion: String) {
        self.executable = executable
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.appName = appName
        self.version = OSVersion(majorVersion: version.majorVersion, minorVersion: version.minorVersion, patchVersion: version.patchVersion)
        self.osName = osName
        self.manufacturer = manufacturer
        self.deviceModel = deviceModel
        self.deviceId = deviceId
        self.environment = environment
        self.sdkVersion = sdkVersion
        self.klaviyoSdk = klaviyoSdk
    }
}

extension UIDevice {
    public enum PushEnvironment: String {
        case unknown
        case development
        case production

        var value: String {
            switch self {
            case .development: return "debug"
            case .production: return "production"
            #if DEBUG
            default: return "debug"
            #else
            default: return "production"
            #endif
            }
        }
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
