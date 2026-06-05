//
//  URLError+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2026-06-03.
//

import Foundation

extension URLError {
    /// `URLError` codes that indicate a genuine offline condition — the only
    /// failures for which waiting on connectivity restoration helps. HTTP errors,
    /// validation rejections, and timeouts are excluded: re-running them once a
    /// path exists wouldn't change the outcome.
    private static let connectivityCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
        .internationalRoamingOff
    ]

    /// `true` when this error represents a genuine offline condition for which
    /// retrying once connectivity is restored is worthwhile (see
    /// ``AuthTokenManager``'s connectivity-driven refresh retry).
    var isConnectivityError: Bool {
        Self.connectivityCodes.contains(code)
    }
}
