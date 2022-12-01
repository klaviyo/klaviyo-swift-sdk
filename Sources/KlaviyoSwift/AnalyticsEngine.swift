//
//  AnalyticsEngine.swift
//  
//
//  Created by Noah Durell on 11/25/22.
//

import Foundation
import Combine

private var cancellable: Cancellable?

struct AnalyticsEngine {
    
    var initialize: (String) -> Void
    var setEmail: (String) -> Void
    var setToken: (Data) -> Void
    var setExternalId: (String) -> Void
    var enqueueLegacyEvent: (String, NSDictionary, NSDictionary) -> Void
    var enqueueLegacyProfile: (NSDictionary) -> Void
    var start: () -> Void
    var stop: () -> Void
    var flush: () -> Void
}

extension AnalyticsEngine {
    struct LegacyEvent {
        let eventName: String
        let customerProperties: NSDictionary
        let properties: NSDictionary
        init(eventName: String,
             customerProperties: NSDictionary?,
             properties: NSDictionary?) {
            self.eventName = eventName
            self.customerProperties = customerProperties ?? NSDictionary()
            self.properties = properties ?? NSDictionary()
        }
    }
    struct LegacyProfile {
        let customerProperties: NSDictionary
    }
    private static var cancellable: Cancellable?
    static let production = Self.init(
        initialize: initialize(with:),
        setEmail: setEmail(email:),
        setToken: setToken(tokenData:),
        setExternalId: setExternalId(externalId:),
        enqueueLegacyEvent: enqueueLegacyEvent(eventName:customerProperties:properties:),
        enqueueLegacyProfile: enqueueLegacyProfile(customerProperties:),
        start: {
            cancellable?.cancel()
            cancellable = Timer.publish(every: 10, on: .main, in: .default)
                .autoconnect()
                .sink(receiveValue: { _ in
                    flushQueue()
                })
        },
        stop: {
            cancellable?.cancel()
        },
        flush: flushQueue
    )
}

extension AnalyticsEngine.LegacyEvent {
    func buildEventRequest(with apiKey: String) throws -> KlaviyoAPI.KlaviyoRequest? {
        guard let eventProperties = self.properties as? [String: Any] else {
            throw KlaviyoAPI.KlaviyoAPIError.invalidData
        }
        guard let customerProperties = self.customerProperties as? [String: Any] else {
            throw KlaviyoAPI.KlaviyoAPIError.invalidData
        }
        let payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload(data: .init(
            attributes: .init(metric: .init(name: self.eventName),
                              properties: eventProperties,
                              profile: customerProperties)))
        let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.createEvent(payload)
        return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
    }
}

extension AnalyticsEngine.LegacyProfile {
    func buildProfileRequest(with apiKey: String, for anonymousId: String) throws -> KlaviyoAPI.KlaviyoRequest? {
        guard var customerProperties = self.customerProperties as? [String: Any] else {
            throw KlaviyoAPI.KlaviyoAPIError.invalidData
        }
        let state = environment.analytics.store.state.value
        // Migrate some properties from properties to v3 API structure.
        let email: String? = customerProperties.removeValue(forKey: "$email") as? String ?? state.email
        let phoneNumber: String? = customerProperties.removeValue(forKey: "$phone_number") as? String ?? state.phoneNumber
        let externalId: String? = customerProperties.removeValue(forKey: "$id") as? String ?? state.externalId
        customerProperties.removeValue(forKey: "$anonymous") // Remove anonymous since we are moving to a uuid (passed in above).
        if let pushToken = environment.analytics.store.state.value.pushToken {
            customerProperties["$ios_tokens"] = pushToken
        }
        let attributes = Klaviyo.Profile.Attributes(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            properties: customerProperties
        )
        let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.createProfile(.init(data: .init(profile: .init(attributes: attributes), anonymousId: anonymousId)))
 
        return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
    }
}

private func initialize(with apiKey: String) {
    dispatchActionOnMainThread(action: .initialize(apiKey))
    environment.analytics.engine.start()
}

private func setEmail(email: String) {
    dispatchActionOnMainThread(action: .setEmail(email))
}

private func setExternalId(externalId: String) {
    dispatchActionOnMainThread(action: .setExternalId(externalId))
}

private func setToken(tokenData: Data) {
    let apnDeviceToken = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
    dispatchActionOnMainThread(action: .setEmail(apnDeviceToken))
}

private func enqueueLegacyEvent(eventName: String,
                        customerProperties: NSDictionary,
                        properties: NSDictionary) {
    let legacyEvent = AnalyticsEngine.LegacyEvent(eventName: eventName, customerProperties: customerProperties, properties: properties)
    let state = environment.analytics.store.state.value
    guard let apiKey = state.apiKey else {
        environment.logger.error("No api key available yet.")
        return
    }
    guard let request = try? legacyEvent.buildEventRequest(with: apiKey) else {
        environment.logger.error("Error build request")
        return
    }
    dispatchActionOnMainThread(action: .enqueueRequest(request))
}

private func enqueueLegacyProfile(customerProperties: NSDictionary) {
    let legacyProfile = AnalyticsEngine.LegacyProfile(customerProperties: customerProperties)
    let state = environment.analytics.store.state.value
    guard let apiKey = state.apiKey else {
        environment.logger.error("No api key available yet.")
        return
    }
    guard let anonymousId = state.anonymousId else {
        environment.logger.error("SDK not initialized yet.")
        return
    }
    guard let request = try? legacyProfile.buildProfileRequest(with: apiKey, for: anonymousId) else {
        environment.logger.error("Error build request")
        return
    }
    dispatchActionOnMainThread(action: .enqueueRequest(request))
}

private func flushQueue() {
    dispatchActionOnMainThread(action: .flushQueue)
}

private func dispatchActionOnMainThread(action: KlaviyoAction) {
    Task {
        await MainActor.run {
            // Store operations need to be run on main thread.
            environment.analytics.store.send(action)
        }
    }
}
