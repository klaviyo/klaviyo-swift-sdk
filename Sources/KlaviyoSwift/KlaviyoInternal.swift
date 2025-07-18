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
    private static var apiKeyCancellable: Cancellable?

    private static let profileDataSubject = CurrentValueSubject<ProfileDataResult, Never>(.failure(.notInitialized))
    private static let apiKeySubject = CurrentValueSubject<APIKeyResult, Never>(.failure(.notInitialized))

    // MARK: - API Key methods

    // Setup the profile data subject to receive updates from the state publisher
    private static func setupAPIKeySubject() {
        // Only set up the subscription if it hasn't already been set up
        guard apiKeyCancellable == nil else { return }

        apiKeyCancellable = klaviyoSwiftEnvironment.statePublisher()
            .map { state -> APIKeyResult in
                guard state.initalizationState == .initialized else {
                    return .failure(.notInitialized)
                }

                guard let apiKey = state.apiKey, !apiKey.isEmpty else {
                    return .failure(.apiKeyNilOrEmpty)
                }

                return .success(apiKey)
            }
            .removeDuplicates()
            .subscribe(apiKeySubject)
    }

    /// A publisher that monitors the API key (aka Company ID) and emits valid API keys.
    ///
    /// - Returns: A publisher that emits valid API keys (non-nil, non-empty strings), or a failure if the API is not initialized or the API key is empty or nil
    package static func apiKeyPublisher() -> AnyPublisher<APIKeyResult, Never> {
        // Set up the subject if it hasn't been set up yet
        setupAPIKeySubject()
        return apiKeySubject.eraseToAnyPublisher()
    }

    /// Fetches the API key once.
    ///
    /// - Returns: The current API key, if available
    /// - Throws: `SDKError.notInitialized` if the SDK is not initialized, or `SDKError.apiKeyNilOrEmpty` if the API key is invalid
    package static func fetchAPIKey() async throws -> String {
        setupAPIKeySubject()

        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = apiKeySubject
                .first()
                .sink { result in
                    switch result {
                    case let .success(apiKey):
                        continuation.resume(returning: apiKey)
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                }
        }
    }

    /// Resets the profile data subject to its initial state.
    package static func resetAPIKeySubject() {
        apiKeyCancellable?.cancel()
        apiKeyCancellable = nil
        apiKeySubject.send(.failure(.notInitialized))
    }

    // MARK: - Profile Data methods

    // Setup the profile data subject to receive updates from the state publisher
    private static func setupProfileDataSubject() {
        // Only set up the subscription if it hasn't already been set up
        guard profileDataCancellable == nil else { return }

        profileDataCancellable = klaviyoSwiftEnvironment.statePublisher()
            .map { state -> ProfileDataResult in
                if state.initalizationState != .initialized {
                    return .failure(.notInitialized)
                }

                return .success(ProfileData(
                    email: state.email,
                    anonymousId: state.anonymousId,
                    phoneNumber: state.phoneNumber,
                    externalId: state.externalId
                ))
            }
            .removeDuplicates()
            .subscribe(profileDataSubject)
    }

    /// Fetches the current profile data once.
    ///
    /// - Returns: The current profile data, if available.
    /// - Throws: `SDKError.notInitialized` if the SDK is not initialized.
    package static func fetchProfileData() async throws -> ProfileData {
        setupProfileDataSubject()

        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = profileDataSubject
                .first()
                .sink { result in
                    switch result {
                    case let .success(profileData):
                        continuation.resume(returning: profileData)
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                }
        }
    }

    package static func profileChangePublisher() -> AnyPublisher<ProfileDataResult, Never> {
        // Set up the subject if it hasn't been set up yet
        setupProfileDataSubject()
        return profileDataSubject.eraseToAnyPublisher()
    }

    /// Resets the profile data subject to its initial state.
    package static func resetProfileDataSubject() {
        profileDataCancellable?.cancel()
        profileDataCancellable = nil
        profileDataSubject.send(.failure(.notInitialized))
    }

    // MARK: - Aggregate Events methods

    /// Create and send an aggregate event.
    ///
    /// - Parameter event: the event to be tracked in Klaviyo
    package static func create(aggregateEvent: AggregateEventPayload) {
        dispatchOnMainThread(action: .enqueueAggregateEvent(aggregateEvent))
    }
}
