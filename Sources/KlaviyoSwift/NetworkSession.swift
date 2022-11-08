//
//  NetworkSession.swift
//  Wrapper class for URLSession.
//
//  Created by Noah Durell on 11/3/22.
//

import Foundation

private let defaultUserAgent = {
    let info = Bundle.main.infoDictionary
    let executable = (info?["CFBundleExecutable"] as? String) ??
        (ProcessInfo.processInfo.arguments.first?.split(separator: "/").last.map(String.init)) ??
        "Unknown"
    let bundle = info?["CFBundleIdentifier"] as? String ?? "Unknown"
    let appVersion = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let appBuild = info?["CFBundleVersion"] as? String ?? "Unknown"

    let osNameVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let osName: String = "iOS"

        return "\(osName) \(versionString)"
    }()

    let klaivyoSDKVersion = "klaviyo-ios/\(version)"

    return "\(executable)/\(appVersion) (\(bundle); build:\(appBuild); \(osNameVersion)) \(klaivyoSDKVersion)"
}()

func createEmphemeralSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpAdditionalHeaders = [
        "Accept-Encoding":  ["br", "gzip", "deflate"],
        "User-Agent": defaultUserAgent
    ]
    return URLSession.init(configuration: configuration)
}

struct NetworkSession {
    var dataTask: (URLRequest, @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> Void
    
    static let production = {
        let session = createEmphemeralSession()
        return NetworkSession { request, completionHandler in
             let task = session.dataTask(with: request, completionHandler: completionHandler)
            task.resume()
        }
    }()
}
