//
//  KlaviyoState.swift
//  
//
//  Created by Noah Durell on 12/1/22.
//

import Foundation

struct KlaviyoState: Encodable {
    var apiKey: String?
    var email: String?
    var anonymousId: String?
    var phoneNumber: String?
    var externalId: String?
    var pushToken: String?
    var queue: [KlaviyoAPI.KlaviyoRequest]
    var requestsInFlight: [KlaviyoAPI.KlaviyoRequest]
    var initialized = false
    var flushing = false
}
