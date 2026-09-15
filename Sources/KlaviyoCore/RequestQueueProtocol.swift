//
//  RequestQueueProtocol.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/11/26.
//

import Foundation

/// Seam over the concrete `RequestQueue` actor so lifecycle wiring can be exercised against a test
/// double that records `start`/`stop`/`flushNow`/`networkConnectivityChanged` invocations.
///
/// `RequestQueue`'s synchronous actor methods satisfy the `async` requirements here: cross-actor
/// calls are already `await`ed at the call site, so the protocol can declare them `async` while the
/// actor implements `start()`/`stop()`/`networkConnectivityChanged(_:)` synchronously.
public protocol RequestQueueProtocol: Sendable {
    func start() async
    func stop() async
    func flushNow() async
    func networkConnectivityChanged(_ status: Reachability.NetworkStatus) async
}

extension RequestQueue: RequestQueueProtocol {}
