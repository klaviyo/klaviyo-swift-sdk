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

    /// How a transport failure is handled by the request queue.
    enum TransportDisposition: Equatable {
        /// Transient: back off and retry.
        case retryable
        /// Permanent: drop the request.
        case drop
        /// Cancelled by the system or caller: not an attempt, keep the request untouched.
        case notAnAttempt
    }

    private static let retryableCodes: Set<URLError.Code> = connectivityCodes.union([
        .timedOut,
        .cannotConnectToHost,
        .resourceUnavailable,
        .cannotFindHost,
        .dnsLookupFailed,
        .zeroByteResource,
        .callIsActive,
        .secureConnectionFailed
    ])

    /// Classifies this transport error for the request queue.
    ///
    /// Retryable: `connectivityCodes` (`notConnectedToInternet`, `networkConnectionLost`,
    /// `dataNotAllowed`, `internationalRoamingOff`), `timedOut`, `cannotConnectToHost`,
    /// `resourceUnavailable`, `cannotFindHost`, `dnsLookupFailed`, `zeroByteResource`,
    /// `callIsActive` and `secureConnectionFailed`.
    /// Not an attempt: `cancelled`.
    /// Drop: every other code, including unlisted codes and certificate errors.
    var transportDisposition: TransportDisposition {
        if code == .cancelled {
            return .notAnAttempt
        }
        return Self.retryableCodes.contains(code) ? .retryable : .drop
    }
}

extension Error {
    /// Maximum number of underlying-error hops followed when looking for a `URLError`.
    static var maxUnderlyingErrorDepth: Int {
        10
    }

    /// The first `URLError` in this error's underlying-error chain, checking the error itself first.
    var firstURLError: URLError? {
        var current: Error? = self
        for _ in 0...Self.maxUnderlyingErrorDepth {
            guard let error = current else { return nil }
            if let urlError = error as? URLError {
                return urlError
            }
            current = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        }
        return nil
    }
}
