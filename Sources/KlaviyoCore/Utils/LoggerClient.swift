//
//  LoggerClient.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 10/21/22.
//

import Foundation
#if canImport(os)
import os
#endif

public struct LoggerClient {
    public init(error: @escaping (String) -> Void) {
        self.error = error
    }

    public var error: (String) -> Void
    public static let production = Self(error: { message in os_log("%{public}s", type: .error, message) })
}

@usableFromInline
@inline(__always)
func runtimeWarn(
    _ message: @autoclosure () -> String,
    category: String? = environment.sdkName(),
    file: StaticString? = nil,
    line: UInt? = nil) {
    #if DEBUG
    let message = message()
    let category = category ?? "Runtime Warning"
    #if canImport(os)
    os_log(
        .fault,
        log: OSLog(subsystem: "com.apple.runtime-issues", category: category),
        "%@",
        message)
    #endif
    #endif
}
