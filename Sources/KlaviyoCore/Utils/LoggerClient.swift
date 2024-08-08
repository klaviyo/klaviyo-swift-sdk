//
//  LoggerClient.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 10/21/22.
//

import Foundation
import os

public struct LoggerClient {
    public var error: (String) -> Void
    public static let production = Self(error: { message in os_log("%{public}s", type: .error, message) })
}
