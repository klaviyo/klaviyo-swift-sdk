//
//  NetworkSession.swift
//  Wrapper class for URLSession.
//
//  Created by Noah Durell on 11/3/22.
//

import Foundation

let CURRENT_API_REVISION = "2022-10-17"
let APPLICATION_JSON = "application/json"
let ACCEPTED_ENCODINGS = ["br", "gzip", "deflate"]

let defaultUserAgent = {
    let appContext = environment.analytics.appContextInfo()
    let klaivyoSDKVersion = "klaviyo-ios/\(version)"
    return "\(appContext.excutable)/\(appContext.appVersion) (\(appContext.bundleId); build:\(appContext.appBuild); \(appContext.osVersionName)) \(klaivyoSDKVersion)"
}()

func createEmphemeralSession(protocolClasses: [AnyClass] = URLProtocolOverrides.protocolClasses) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpAdditionalHeaders = [
        "Accept-Encoding":  ACCEPTED_ENCODINGS,
        "User-Agent": defaultUserAgent,
        "revision": CURRENT_API_REVISION,
        "content-type": APPLICATION_JSON,
        "accept": APPLICATION_JSON
    ]
    configuration.protocolClasses = protocolClasses
    return URLSession.init(configuration: configuration)
}

struct NetworkSession {
    var data: (URLRequest) async throws -> (Data, URLResponse)
    
    static let production = {
        let session = createEmphemeralSession()
        return NetworkSession(data: session.data(for:))
    }()
}

public struct URLProtocolOverrides {
    public static var protocolClasses = [AnyClass]()
}
