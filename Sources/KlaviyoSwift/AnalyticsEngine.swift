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
    var enqueueLegacyEvent: (String, NSDictionary, NSDictionary) -> Void
    var enqueueLegacyProfile: (NSDictionary) -> Void
    var start: () -> Void
    var stop: () -> Void
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
    static var cancellable: Cancellable?
    static let production = Self.init(
        initialize: initialize(with:),
        setEmail: setEmail(email:),
        setToken: setToken(tokenData:),
        enqueueLegacyEvent: enqueueLegacyEvent(eventName:customerProperties:properties:),
        enqueueLegacyProfile: enqueueLegacyProfile(customerProperties:),
        start: {
            cancellable = Timer.publish(every: 1, on: .main, in: .default)
                .autoconnect()
                .sink(receiveValue: { _ in
                    dispatchActionOnMainThread(action: .flushQueue)
                })
        },
        stop: {
            cancellable?.cancel()
        }
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
    func buildProfileRequest(with apiKey: String) throws -> KlaviyoAPI.KlaviyoRequest? {
        guard var customerProperties = self.customerProperties as? [String: Any] else {
            throw KlaviyoAPI.KlaviyoAPIError.invalidData
        }
        let email: String? = customerProperties.removeValue(forKey: "$email") as? String
        let phoneNumber: String? = customerProperties.removeValue(forKey: "$email") as? String
        let anonymousId: String = customerProperties.removeValue(forKey: "$anonymous") as? String ?? "" //TODO: get anonymous id properly
        let externalId: String? = customerProperties.removeValue(forKey: "$id") as? String
        if let pushToken = environment.analytics.store.state.value.pushToken {
            customerProperties["$ios_tokens"] = pushToken
        }
        let attributes = Klaviyo.Profile.Attributes(
            email: email, phoneNumber: phoneNumber, externalId: externalId, properties: customerProperties)
        let endpoint = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.createProfile(.init(data: .init(profile: .init(attributes: attributes), anonymousId: anonymousId)))
 
        return KlaviyoAPI.KlaviyoRequest(apiKey: apiKey, endpoint: endpoint)
    }
}

func initialize(with apiKey: String) {
    dispatchActionOnMainThread(action: .initialize(apiKey))
}

func setEmail(email: String) {
    dispatchActionOnMainThread(action: .setEmail(email))
}

func setToken(tokenData: Data) {
    let apnDeviceToken = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
    dispatchActionOnMainThread(action: .setEmail(apnDeviceToken))
}

func enqueueLegacyEvent(eventName: String,
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

func enqueueLegacyProfile(customerProperties: NSDictionary) {
    let legacyProfile = AnalyticsEngine.LegacyProfile(customerProperties: customerProperties)
    let state = environment.analytics.store.state.value
    guard let apiKey = state.apiKey else {
        environment.logger.error("No api key available yet.")
        return
    }
    guard let request = try? legacyProfile.buildProfileRequest(with: apiKey) else {
        environment.logger.error("Error build request")
        return
    }
    dispatchActionOnMainThread(action: .enqueueRequest(request))
}

func dispatchActionOnMainThread(action: KlaviyoAction) {
    Task {
        await MainActor.run {
            // Store operations need to be run on main thread.
            environment.analytics.store.send(action)
        }
    }
}
