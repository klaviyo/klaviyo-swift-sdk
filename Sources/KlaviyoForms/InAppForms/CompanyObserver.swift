//
//  CompanyObserver.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/25.
//
import Combine
import Foundation
import KlaviyoCore
import KlaviyoSwift

class CompanyObserver: JSBridgeObserver {
    private var apiKeyCancellable: AnyCancellable?

    func startObserving() {
        apiKeyCancellable = KlaviyoInternal.apiKeyPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }

                switch result {
                case let .success(apiKey):
                    break
//                    if let config = self.configuration {
//                        self.handleAPIKeyReceived(apiKey, configuration: config)
//                    }
                case let .failure(sdkError):
                    break
//                    self.handleAPIKeyError(sdkError)
                }
            }
    }

    func stopObserving() {
        apiKeyCancellable?.cancel()
        apiKeyCancellable = nil
    }
}
