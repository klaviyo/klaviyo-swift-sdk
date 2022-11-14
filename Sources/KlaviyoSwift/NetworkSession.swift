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

func createEmphemeralSession(protocolClasses: [AnyClass] = []) -> URLSession {
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
    static var protocolClasses: [AnyClass] = []
    var dataTask: (URLRequest, @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> Void
    
    static let production = {
        let session = createEmphemeralSession(protocolClasses: protocolClasses)
        return NetworkSession { request, completionHandler in
             let task = session.dataTask(with: request, completionHandler: completionHandler)
            task.resume()
        }
    }()
}
