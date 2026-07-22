@testable import KlaviyoCore
import XCTest

final class KlaviyoEndpointTests: XCTestCase {
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        environment.encodeJSON = { body in
            try JSONEncoder().encode(body)
        }
    }

    func testCreateProfileEndpointUrlRequest() throws {
        // Given
        let apiKey = "test_api_key"
        let payload = CreateProfilePayload(data: ProfilePayload.test)
        let endpoint = KlaviyoEndpoint.createProfile(apiKey, payload)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/client/profiles")
        XCTAssertEqual(request.url?.query, "company_id=test_api_key")
        XCTAssertNotNil(request.httpBody)
    }

    func testCreateEventEndpointUrlRequest() throws {
        // Given
        let apiKey = "test_api_key"
        let payload = CreateEventPayload(data: CreateEventPayload.Event(name: "test_event"))
        let endpoint = KlaviyoEndpoint.createEvent(apiKey, payload)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/client/events")
        XCTAssertEqual(request.url?.query, "company_id=test_api_key")
        XCTAssertNotNil(request.httpBody)
    }

    func testRegisterPushTokenEndpointUrlRequest() throws {
        // Given
        let apiKey = "test_api_key"
        let payload = PushTokenPayload.test
        let endpoint = KlaviyoEndpoint.registerPushToken(apiKey, payload)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/client/push-tokens")
        XCTAssertEqual(request.url?.query, "company_id=test_api_key")
        XCTAssertNotNil(request.httpBody)
    }

    func testUnregisterPushTokenEndpointUrlRequest() throws {
        // Given
        let apiKey = "test_api_key"
        let payload = UnregisterPushTokenPayload(pushToken: "test_token", anonymousId: "anon-id")
        let endpoint = KlaviyoEndpoint.unregisterPushToken(apiKey, payload)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/client/push-token-unregister")
        XCTAssertEqual(request.url?.query, "company_id=test_api_key")
        XCTAssertNotNil(request.httpBody)
    }

    func testAggregateEventEndpointUrlRequest() throws {
        // Given
        let apiKey = "test_api_key"
        let payload = Data("test_payload".utf8)
        let endpoint = KlaviyoEndpoint.aggregateEvent(apiKey, payload)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/onsite/track-analytics")
        XCTAssertEqual(request.url?.query, "company_id=test_api_key")
        XCTAssertNotNil(request.httpBody)
        XCTAssertEqual(request.httpBody, payload)
    }

    func testResolveDestinationURLEndpointUrlRequest() throws {
        // Given
        let trackingLink = URL(string: "https://email.klaviyo.com/tracking/link")!
        let profileInfo = ProfilePayload(email: "test@example.com", phoneNumber: "+15551234567", externalId: "user-123", anonymousId: "anon-456")
        let endpoint = KlaviyoEndpoint.resolveDestinationURL(trackingLink: trackingLink, profileInfo: profileInfo)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, trackingLink.absoluteString)
        XCTAssertNil(request.url?.query) // No query items for this endpoint
        XCTAssertNil(request.httpBody) // No body for this endpoint

        // Test headers
        if let profileData = try? environment.encodeJSON(profileInfo),
           let profileDataString = String(data: profileData, encoding: .utf8),
           let headerValue = request.allHTTPHeaderFields?["X-Klaviyo-Profile-Info"] {
            // Decode Base64 header value back to JSON string
            guard let decodedData = Data(base64Encoded: headerValue),
                  let decodedJsonString = String(data: decodedData, encoding: .utf8) else {
                XCTFail("Failed to decode Base64 header value")
                return
            }

            // Compare JSON objects instead of string representations to avoid order issues
            let profileJson = try JSONSerialization.jsonObject(with: Data(profileDataString.utf8), options: []) as! [String: Any]
            let headerJson = try JSONSerialization.jsonObject(with: Data(decodedJsonString.utf8), options: []) as! [String: Any]

            // Compare the type
            XCTAssertEqual(profileJson["type"] as? String, headerJson["type"] as? String)

            // Compare attributes as dictionaries
            let profileAttrs = profileJson["attributes"] as! [String: Any]
            let headerAttrs = headerJson["attributes"] as! [String: Any]

            XCTAssertEqual(profileAttrs["email"] as? String, headerAttrs["email"] as? String)
            XCTAssertEqual(profileAttrs["phone_number"] as? String, headerAttrs["phone_number"] as? String)
            XCTAssertEqual(profileAttrs["external_id"] as? String, headerAttrs["external_id"] as? String)
            XCTAssertEqual(profileAttrs["anonymous_id"] as? String, headerAttrs["anonymous_id"] as? String)
        } else {
            XCTFail("Failed to encode profile info for header")
        }
    }

    func testPathValidation() throws {
        // Given
        environment.apiURL = {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "test.klaviyo.com"
            return components
        }

        // Test with a valid endpoint
        let endpoint = KlaviyoEndpoint.createProfile("api_key", CreateProfilePayload(data: ProfilePayload.test))

        // When/Then
        XCTAssertNoThrow(try endpoint.urlRequest())
    }

    func testInvalidURL() throws {
        // Given
        environment.apiURL = {
            // Invalid URL components with no scheme or host
            URLComponents()
        }

        let endpoint = KlaviyoEndpoint.createProfile("api_key", CreateProfilePayload(data: ProfilePayload.test))

        // When/Then
        XCTAssertThrowsError(try endpoint.urlRequest()) { error in
            guard let apiError = error as? KlaviyoAPIError else {
                XCTFail("Expected KlaviyoAPIError")
                return
            }

            switch apiError {
            case let .internalError(message):
                XCTAssertTrue(message.contains("Failed to build valid URL"))
            default:
                XCTFail("Expected internalError")
            }
        }
    }

    func testFetchGeofencesEndpointUrlRequest() throws {
        // Given
        let apiKey = "test_api_key"
        let latitude = 37.7749
        let longitude = -122.4194
        let endpoint = KlaviyoEndpoint.fetchGeofences(apiKey, latitude: latitude, longitude: longitude)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/client/geofences")
        let queryItems = request.url?.query?.components(separatedBy: "&").sorted() ?? []
        XCTAssertTrue(queryItems.contains("company_id=test_api_key"))
        XCTAssertTrue(queryItems.contains("page%5Bsize%5D=30"))
        XCTAssertFalse(queryItems.contains { $0.contains("latitude") })
        XCTAssertFalse(queryItems.contains { $0.contains("longitude") })

        // Check header
        let headerValue = request.allHTTPHeaderFields?["X-Klaviyo-API-Filters"]
        XCTAssertEqual(headerValue, "and(equals(lat,37.7749),equals(lng,-122.4194))")
    }

    func testFetchGeofencesEndpointUrlRequestWithLatLon() throws {
        // Given
        let apiKey = "test_api_key"
        let latitude = 42.33
        let longitude = -71.05
        let endpoint = KlaviyoEndpoint.fetchGeofences(apiKey, latitude: latitude, longitude: longitude)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/client/geofences")
        let queryItems = request.url?.query?.components(separatedBy: "&").sorted() ?? []
        XCTAssertTrue(queryItems.contains("company_id=test_api_key"))
        XCTAssertTrue(queryItems.contains("page%5Bsize%5D=30"))
        XCTAssertFalse(queryItems.contains { $0.contains("latitude") })
        XCTAssertFalse(queryItems.contains { $0.contains("longitude") })

        // Check header
        let headerValue = request.allHTTPHeaderFields?["X-Klaviyo-API-Filters"]
        XCTAssertEqual(headerValue, "and(equals(lat,42.33),equals(lng,-71.05))")
    }

    func testFetchGeofencesEndpointUrlRequestWithNilCoordinates() throws {
        // Given
        let apiKey = "test_api_key"
        let endpoint = KlaviyoEndpoint.fetchGeofences(apiKey, latitude: nil, longitude: nil)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/client/geofences")
        let queryItems = request.url?.query?.components(separatedBy: "&").sorted() ?? []
        XCTAssertTrue(queryItems.contains("company_id=test_api_key"))
        XCTAssertTrue(queryItems.contains("page%5Bsize%5D=30"))
        XCTAssertFalse(queryItems.contains { $0.contains("latitude") })
        XCTAssertFalse(queryItems.contains { $0.contains("longitude") })

        // Check that header is not present when coordinates are nil
        XCTAssertNil(request.allHTTPHeaderFields?["X-Klaviyo-API-Filters"])
    }

    func testRevisionHeaderForGeofenceEndpoint() throws {
        // Given
        let apiKey = "test_api_key"
        let latitude = 37.7749
        let longitude = -122.4194
        let endpoint = KlaviyoEndpoint.fetchGeofences(apiKey, latitude: latitude, longitude: longitude)
        let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 1)
        let request = KlaviyoRequest(endpoint: endpoint)

        // When
        let urlRequest = try request.urlRequest(attemptInfo: attemptInfo)

        // Then
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "revision"), "2026-01-15.pre")
    }

    func testRevisionHeaderForNonGeofenceEndpoints() throws {
        let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 50)

        // Test createProfile
        let profileEndpoint = KlaviyoEndpoint.createProfile("test_api_key", CreateProfilePayload(data: ProfilePayload.test))
        let profileRequest = KlaviyoRequest(endpoint: profileEndpoint)
        let profileUrlRequest = try profileRequest.urlRequest(attemptInfo: attemptInfo)
        XCTAssertEqual(profileUrlRequest.value(forHTTPHeaderField: "revision"), "2026-01-15")

        // Test createEvent (including geofence events use standard revision)
        let eventEndpoint = KlaviyoEndpoint.createEvent("test_api_key", CreateEventPayload(data: CreateEventPayload.Event(name: "test_event")))
        let eventRequest = KlaviyoRequest(endpoint: eventEndpoint)
        let eventUrlRequest = try eventRequest.urlRequest(attemptInfo: attemptInfo)
        XCTAssertEqual(eventUrlRequest.value(forHTTPHeaderField: "revision"), "2026-01-15")

        // Test geofence event also uses standard revision
        let geofenceEventEndpoint = KlaviyoEndpoint.createEvent("test_api_key", CreateEventPayload(data: CreateEventPayload.Event(name: "$geofence_enter")))
        let geofenceEventRequest = KlaviyoRequest(endpoint: geofenceEventEndpoint)
        let geofenceEventUrlRequest = try geofenceEventRequest.urlRequest(attemptInfo: attemptInfo)
        XCTAssertEqual(geofenceEventUrlRequest.value(forHTTPHeaderField: "revision"), "2026-01-15")
    }

    // MARK: - Create Subscription Tests

    func testCreateSubscriptionEndpointUrlRequest() throws {
        // Given
        let apiKey = "test_api_key"
        let payload = CreateSubscriptionPayload.test
        let endpoint = KlaviyoEndpoint.createSubscription(apiKey, payload)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/client/subscriptions")
        XCTAssertEqual(request.url?.query, "company_id=test_api_key")
        XCTAssertNotNil(request.httpBody)

        let body = try XCTUnwrap(request.httpBody)
        let jsonObject = try JSONSerialization.jsonObject(with: body, options: [])
        let json = try XCTUnwrap(jsonObject as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        XCTAssertNil(attributes["custom_source"])

        let profile = try XCTUnwrap(attributes["profile"] as? [String: Any])
        let profileData = try XCTUnwrap(profile["data"] as? [String: Any])
        let profileAttrs = try XCTUnwrap(profileData["attributes"] as? [String: Any])
        XCTAssertNil(
            profileAttrs["subscriptions"],
            "omitting channels must omit subscriptions so the API can default to MARKETING"
        )
    }

    func testCreateSubscriptionEndpointWithChannels() throws {
        // Given
        let apiKey = "test_api_key"
        let payload = CreateSubscriptionPayload.testWithChannels
        let endpoint = KlaviyoEndpoint.createSubscription(apiKey, payload)

        // When
        let request = try endpoint.urlRequest()

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/client/subscriptions")
        XCTAssertEqual(request.url?.query, "company_id=test_api_key")
        XCTAssertNotNil(request.httpBody)

        let body = try XCTUnwrap(request.httpBody, "createSubscription request must include an httpBody")
        let jsonObject = try JSONSerialization.jsonObject(with: body, options: [])
        let json = try XCTUnwrap(jsonObject as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])

        let relationships = try XCTUnwrap(data["relationships"] as? [String: Any])
        let list = try XCTUnwrap(relationships["list"] as? [String: Any])
        let listData = try XCTUnwrap(list["data"] as? [String: Any])
        XCTAssertEqual(listData["type"] as? String, "list")
        XCTAssertEqual(listData["id"] as? String, "test-list-id")

        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        XCTAssertNil(attributes["list_id"], "list must be a relationship, not a flat attribute")
        XCTAssertNil(
            attributes["subscriptions"],
            "consent must be nested inside the profile, not at top level"
        )
        XCTAssertEqual(attributes["custom_source"] as? String, "unit-test")

        // attributes.profile.data.attributes.subscriptions.email.marketing.consent == "SUBSCRIBED"
        let profile = try XCTUnwrap(attributes["profile"] as? [String: Any])
        let profileData = try XCTUnwrap(profile["data"] as? [String: Any])
        let profileAttrs = try XCTUnwrap(profileData["attributes"] as? [String: Any])
        let subscriptions = try XCTUnwrap(profileAttrs["subscriptions"] as? [String: Any])

        // Email: marketing + open_tracking.
        let email = try XCTUnwrap(subscriptions["email"] as? [String: Any])
        XCTAssertEqual((email["marketing"] as? [String: Any])?["consent"] as? String, "SUBSCRIBED")
        XCTAssertEqual((email["open_tracking"] as? [String: Any])?["consent"] as? String, "SUBSCRIBED")

        // SMS: marketing + transactional.
        let sms = try XCTUnwrap(subscriptions["sms"] as? [String: Any])
        XCTAssertEqual((sms["marketing"] as? [String: Any])?["consent"] as? String, "SUBSCRIBED")
        XCTAssertEqual((sms["transactional"] as? [String: Any])?["consent"] as? String, "SUBSCRIBED")

        // WhatsApp: marketing + transactional.
        let whatsapp = try XCTUnwrap(subscriptions["whatsapp"] as? [String: Any])
        XCTAssertEqual((whatsapp["marketing"] as? [String: Any])?["consent"] as? String, "SUBSCRIBED")
        XCTAssertEqual((whatsapp["transactional"] as? [String: Any])?["consent"] as? String, "SUBSCRIBED")
    }

    func testCreateSubscriptionEndpointWithPartialChannels() throws {
        // Given
        let apiKey = "test_api_key"
        let payload = CreateSubscriptionPayload.testWithPartialChannels
        let endpoint = KlaviyoEndpoint.createSubscription(apiKey, payload)

        // When
        let request = try endpoint.urlRequest()

        // Then
        let body = try XCTUnwrap(request.httpBody, "createSubscription request must include an httpBody")
        let jsonObject = try JSONSerialization.jsonObject(with: body, options: [])
        let json = try XCTUnwrap(jsonObject as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        let profile = try XCTUnwrap(attributes["profile"] as? [String: Any])
        let profileData = try XCTUnwrap(profile["data"] as? [String: Any])
        let profileAttrs = try XCTUnwrap(profileData["attributes"] as? [String: Any])
        let subscriptions = try XCTUnwrap(profileAttrs["subscriptions"] as? [String: Any])

        // Only the requested sub-type is present.
        let sms = try XCTUnwrap(subscriptions["sms"] as? [String: Any])
        XCTAssertEqual((sms["marketing"] as? [String: Any])?["consent"] as? String, "SUBSCRIBED")
        XCTAssertNil(sms["transactional"], "unrequested sms.transactional must be absent from the payload")

        // Unrequested channels are entirely absent.
        XCTAssertNil(subscriptions["email"], "unrequested email channel must be absent from the payload")
        XCTAssertNil(subscriptions["whatsapp"], "unrequested whatsapp channel must be absent from the payload")
    }

    func testCreateSubscriptionEndpointRevision() throws {
        // Given
        let apiKey = "test_api_key"
        let payload = CreateSubscriptionPayload.test
        let endpoint = KlaviyoEndpoint.createSubscription(apiKey, payload)
        let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 50)
        let request = KlaviyoRequest(endpoint: endpoint)

        // When
        let urlRequest = try request.urlRequest(attemptInfo: attemptInfo)

        // Then
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "revision"), "2026-01-15")
    }
}
