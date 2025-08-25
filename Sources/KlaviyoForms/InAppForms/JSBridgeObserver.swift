//
//  JSBridgeObserver.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/25.
//

import Foundation

// General purpose observer interface for bridging native/SDK events into the webview
protocol JSBridgeObserver {
    // Start observing events and passing data into the webview
    func startObserving()

    // Stop observer, detach listeners, clean up resources
    func stopObserving()
}
