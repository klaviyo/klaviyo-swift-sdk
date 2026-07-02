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
    private static let profileDataSubject = CurrentValueSubject<ProfileDataResult, Never>(.failure(.notInitialized))

    private static var apiKeyCancellable: Cancellable?
    private static let apiKeySubject = CurrentValueSubject<APIKeyResult, Never>(.failure(.notInitialized))

    private static var sharedStoresCancellable: Cancellable?

    private static let profileEventSubject = PassthroughSubject<Event, Never>()
    private static var profileEventCancellable: Cancellable?
    private static let eventBuffer = EventBuffer(maxBufferSize: 10, maxBufferAge: 10)

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
    /// - Returns: A publisher that emits valid API keys (non-nil, non-empty strings),
    //             or a failure if the API is not initialized or the API key is empty or nil
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
        // Defensive, idempotent attach of the shared-store mirror. The mirror is normally
        // established at `initialize(with:)` and left alive for the SDK's lifetime — it is NOT
        // torn down on In-App Forms teardown (see `resetProfileDataSubject()`), so this is a
        // safety net rather than a required re-attach hook.
        setupSharedStores()

        // Only set up the subscription if it hasn't already been set up
        guard profileDataCancellable == nil else { return }

        profileDataCancellable = klaviyoSwiftEnvironment.statePublisher()
            .map { state -> ProfileDataResult in
                if state.initalizationState != .initialized {
                    return .failure(.notInitialized)
                }

                return .success(state.identity)
            }
            .removeDuplicates()
            .subscribe(profileDataSubject)
    }

    /// Mirrors initialized SDK state into the shared `KlaviyoCore` stores so other modules
    /// (Forms, Location) can observe identity and API key without importing `KlaviyoSwift`.
    package static func setupSharedStores() {
        guard sharedStoresCancellable == nil else { return }
        sharedStoresCancellable = klaviyoSwiftEnvironment.statePublisher()
            .filter { $0.initalizationState == .initialized }
            .map { (identity: $0.identity, apiKey: $0.apiKey) }
            .removeDuplicates(by: { $0.identity == $1.identity && $0.apiKey == $1.apiKey })
            // TCA dispatches state changes on the main thread, so these two sequential
            // store writes are observed together rather than torn. Write the config
            // before the identity: IdentityStore.update(_:) notifies observers
            // synchronously, so an identity observer must not see a stale apiKey.
            .sink { identity, apiKey in
                SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
                IdentityStore.shared.update(identity)
            }
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
        // NOTE: deliberately does NOT tear down the shared-store mirror or clear the stores.
        // The mirror is global SDK state (established once by `setupSharedStores()` at
        // initialize) that KlaviyoForms/KlaviyoLocation observe directly. Clearing it on
        // In-App Forms teardown would leave the stores empty after an unregister → re-register
        // cycle even while the SDK stays initialized, since consumers now read the stores
        // directly and no longer re-trigger `setupSharedStores()`. (Broader teardown
        // decoupling is tracked in MAGE-834.)
    }

    /// Tears down the shared-store mirror and clears the stores. **Test-only isolation helper** —
    /// production never tears the mirror down (see `resetProfileDataSubject()`); this exists so
    /// tests that call `setupSharedStores()` start from a detached, empty state.
    package static func resetSharedStores() {
        sharedStoresCancellable?.cancel()
        sharedStoresCancellable = nil
        SDKConfigStore.shared.update(KlaviyoConfig())
        IdentityStore.shared.update(ProfileData())
    }

    // MARK: - Profile Event methods

    /// Publishes an event to subscribers and also buffers it for replay to future subscribers.
    ///
    /// - Parameter event: the profile event to publish
    internal static func publishEvent(_ event: Event) {
        let enrichedEvent = enrichEventWithMetadata(event)
        eventBuffer.buffer(enrichedEvent)
        profileEventSubject.send(enrichedEvent)
    }

    /// A publisher that emits events when they are created.
    ///
    /// Replays recently buffered events (up to 10 events or 10 seconds old) to new subscribers,
    /// then continues emitting new events as they are published. This handles the race condition
    /// where events may be published before subscribers (e.g., "Opened Push" before forms initialization).
    ///
    /// - Returns: A publisher that emits profile events plus any buffered events
    package static func eventPublisher() -> AnyPublisher<Event, Never> {
        Deferred {
            let buffered = eventBuffer.getRecentEvents()
            return profileEventSubject
                .prepend(buffered) // guaranteed order: replay first, then live
        }
        .eraseToAnyPublisher()
    }

    /// Resets the profile event subject to its initial state.
    package static func resetEventSubject() {
        profileEventCancellable?.cancel()
        profileEventCancellable = nil
    }

    /// Clears the event buffer to ensure clean state between tests.
    /// This prevents events from previous tests from being replayed in new tests.
    package static func clearEventBuffer() {
        eventBuffer.clear()
    }

    /// Enriches an event with metadata (device info, SDK info, etc.)
    /// - Parameter event: The event to enrich
    /// - Returns: A new Event with metadata appended to properties
    private static func enrichEventWithMetadata(_ event: Event) -> Event {
        let enrichedProperties = event.properties.appendMetadataToProperties() ?? event.properties
        return Event(
            name: event.metric.name,
            properties: enrichedProperties,
            identifiers: event.identifiers,
            value: event.value,
            time: event.time,
            uniqueId: event.uniqueId
        )
    }

    // MARK: - Aggregate Events methods

    /// Create and send an aggregate event.
    ///
    /// - Parameter event: the event to be tracked in Klaviyo
    package static func create(aggregateEvent: AggregateEventPayload) {
        dispatchOnMainThread(action: .enqueueAggregateEvent(aggregateEvent))
    }

    // MARK: - Events methods

    /// Create and send an event.
    ///
    /// - Parameter event: the event to be tracked in Klaviyo
    package static func create(event: Event) {
        dispatchOnMainThread(action: .enqueueEvent(event))
    }

    // MARK: - Geofence Event

    /// Send a geofence event to Klaviyo.
    /// If the SDK is not yet initialized, it will automatically initialize using the API key extracted from the geofence.
    /// If the SDK is already initialized with a different API key, the event will be ignored.
    ///
    /// - Parameters:
    ///   - apiKey: The API key (company ID) extracted from the geofence event
    ///   - event: The geofence event to be sent
    @MainActor
    package static func createGeofenceEvent(event: Event, for apiKey: String) async {
        if let storedApiKey = try? await fetchAPIKey() {
            guard storedApiKey == apiKey else {
                return
            }
            dispatchOnMainThread(action: .enqueueEvent(event))
        } else {
            dispatchOnMainThread(action: .initialize(apiKey))
            dispatchOnMainThread(action: .enqueueEvent(event))
        }
    }

    // MARK: - Deep link handling

    /// Handles a deep link according to the handler configured in `klaviyoSwiftEnvironment`
    /// - Parameter url: the URL of the deep link to be handled
    package static func handleDeepLink(url: URL) {
        dispatchOnMainThread(action: .openDeepLink(url))
    }
}
