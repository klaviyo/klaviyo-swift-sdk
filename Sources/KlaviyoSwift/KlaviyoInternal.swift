//
//  KlaviyoSDK.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/4/25.
//

import Combine
import Foundation
import KlaviyoCore

/// The internal interface for the Klaviyo SDK.
///
/// - Note: Can only be accessed from other modules within the Klaviyo-Swift-SDK package; cannot be accessed from the host app.
package enum KlaviyoInternal {
    static var cancellable: Cancellable?
    /// the apiKey (a.k.a. CompanyID) for the current SDK instance.
    /// - Parameter completion: completion hanlder that will be called when apiKey is avaialble after SDK is initilized
    package static func apiKey(completion: @escaping ((String?) -> Void)) {
        if cancellable == nil {
            cancellable = KlaviyoSwiftEnvironment.production.statePublisher()
                .receive(on: DispatchQueue.main)
                .filter { $0.initalizationState == .initialized }
                .compactMap(\.apiKey)
                .removeDuplicates()
                .prefix(1)
                .sink(receiveValue: {
                    completion($0)
                    cancellable = nil
                })
        }
    }

    package static func profileChangePublisher() -> AnyPublisher<ProfileData, Never> {
        klaviyoSwiftEnvironment.statePublisher()
            .removeDuplicates()
            .map {
                ProfileData(
                    apiKey: $0.apiKey,
                    email: $0.email,
                    anonymousId: $0.anonymousId,
                    phoneNumber: $0.phoneNumber,
                    externalId: $0.externalId
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Create and send an aggregate event.
    /// - Parameter event: the event to be tracked in Klaviyo
    package static func create(aggregateEvent: AggregateEventPayload) {
        dispatchOnMainThread(action: .enqueueAggregateEvent(aggregateEvent))
    }

    /// A publisher that monitors the API key (aka Company ID) and emits valid API keys.
    ///
    /// If a nil or empty string is received, it will start a 10-second timer and log a warning if no valid key is received before the timer elapses.
    /// - Returns: A publisher that emits valid API keys (non-nil, non-empty strings)
    package static func apiKeyPublisher() -> AnyPublisher<String, Never> {
        profileChangePublisher()
            .map(\.apiKey)
            .removeDuplicates()
            .map { apiKey -> AnyPublisher<String?, Never> in
                if let apiKey = apiKey, !apiKey.isEmpty {
                    // If we get a valid key, emit it immediately and cancel any pending timer
                    return Just(apiKey).eraseToAnyPublisher()
                } else {
                    // If we get nil or empty string, start a timer that will emit a warning after 10 seconds
                    return Just(nil)
                        .delay(for: .seconds(10), scheduler: DispatchQueue.main)
                        .handleEvents(receiveOutput: { _ in
                            environment.emitDeveloperWarning("SDK must be initialized before usage.")
                        })
                        .eraseToAnyPublisher()
                }
            }
            .switchToLatest()
            .compactMap { $0 } // Only emit non-nil values
            .filter { !$0.isEmpty }
            .eraseToAnyPublisher()
    }
}
