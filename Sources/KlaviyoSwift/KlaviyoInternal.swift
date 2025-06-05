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
    package enum ProfileDataResult: Equatable {
        case success(ProfileData)
        case failure(SDKError)
    }

    package enum APIKeyResult: Equatable {
        case success(String)
        case failure(SDKError)
    }

    private static var profileDataCancellable: Cancellable?

    // Single source of truth for profile data
    private static let profileDataSubject = CurrentValueSubject<ProfileDataResult, Never>(.failure(.notInitialized))

    // Setup the profile data subject to receive updates from the state publisher
    private static func setupProfileDataSubject() {
        // Only set up the subscription if it hasn't already been set up
        guard profileDataCancellable == nil else { return }

        profileDataCancellable = klaviyoSwiftEnvironment.statePublisher()
            .map { state -> ProfileDataResult in
                if state.initalizationState != .initialized {
                    return .failure(.notInitialized)
                }

                guard let apiKey = state.apiKey,!apiKey.isEmpty else {
                    return .failure(.apiKeyNilOrEmpty)
                }

                return .success(ProfileData(
                    apiKey: state.apiKey,
                    email: state.email,
                    anonymousId: state.anonymousId,
                    phoneNumber: state.phoneNumber,
                    externalId: state.externalId
                ))
            }
            .removeDuplicates()
            .subscribe(profileDataSubject)
    }

    package static func profileChangePublisher() -> AnyPublisher<ProfileDataResult, Never> {
        // Set up the subject if it hasn't been set up yet
        setupProfileDataSubject()
        return profileDataSubject.eraseToAnyPublisher()
    }

    /// A publisher that monitors the API key (aka Company ID) and emits valid API keys.
    ///
    /// - Returns: A publisher that emits valid API keys (non-nil, non-empty strings), or a failure if the API is not initialized or the API key is empty or nil
    package static func apiKeyPublisher() -> AnyPublisher<APIKeyResult, Never> {
        setupProfileDataSubject()

        return profileDataSubject
            .map { result -> APIKeyResult in
                switch result {
                case let .success(profileData):
                    guard let apiKey = profileData.apiKey,!apiKey.isEmpty else {
                        return .failure(.apiKeyNilOrEmpty)
                    }
                    return .success(apiKey)
                case let .failure(error):
                    return .failure(error)
                }
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Create and send an aggregate event.
    ///
    /// - Parameter event: the event to be tracked in Klaviyo
    package static func create(aggregateEvent: AggregateEventPayload) {
        dispatchOnMainThread(action: .enqueueAggregateEvent(aggregateEvent))
    }
}
