//
//  JSBridgeObserver.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/25.
//

import Combine
import Foundation
import KlaviyoCore
import KlaviyoSwift

protocol JSBridgeObserver {
    func startObserving()
    func stopObserving()
}
