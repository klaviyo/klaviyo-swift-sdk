//
//  URLError+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2026-06-03.
//

import Foundation

extension URLError {
    /// `URLError` codes that indicate a genuine offline condition — the only
    /// failures for which waiting on connectivity restoration is the right
    /// remedy. HTTP error responses, validation rejections, and generic
    /// timeouts are deliberately excluded: re-running the same request once a
    /// path exists would not change their outcome.
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
