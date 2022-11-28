//
//  AnalyticsEngine.swift
//  
//
//  Created by Noah Durell on 11/25/22.
//

import Foundation

struct AnalyticsEngine {
    var initialize: (String) -> Void
    var setEmail: (String) -> Void
    var setToken: (Data) -> Void
    var enqueueLegacyEvent: (String, NSDictionary?, NSDictionary?) -> Void
    var enqueueLegacyProfile: (NSDictionary) -> Void
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
    static let production = Self.init(
        initialize: initialize(with:),
        setEmail: setEmail(email:),
        setToken: setToken(tokenData:),
        enqueueLegacyEvent: enqueueLegacyEvent(eventName:customerProperties:properties:),
        enqueueLegacyProfile: enqueueLegacyProfile(customerProperties:),
        flush: {}
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

func initialize(with apiKey: String) {
    
}

func setEmail(email: String) {
    
}

func setToken(tokenData: Data) {
    
}

func enqueueLegacyEvent(eventName: String,
                        customerProperties: NSDictionary?,
                        properties: NSDictionary?) {
    
}

func enqueueLegacyProfile(customerProperties: NSDictionary?) {
}
