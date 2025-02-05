//
//  IAFNativeBridgeEventTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/3/25.
//

@testable import KlaviyoUI
import AnyCodable
import Foundation

#if canImport(Testing)
import Testing

struct IAFNativeBridgeEventTests {
    @Test func testDecodeOpenDeepLink() async throws {
        let json = """
        {
          "type": "openDeepLink",
          "data": {
            "ios": "klaviyotest://settings",
            "android": "klaviyotest://settings"
          }
        }
        """

        let deepLinkEvent = """
        {
            "ios": "klaviyotest://settings",
            "android": "klaviyotest://settings"
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: data)
        guard case let .openDeepLink(url) = event else {
            Issue.record("event type should be .openDeepLink but was '.\(event)'")
            return
        }
        let deepLinkEventData = try #require(deepLinkEvent.data(using: .utf8))
        let deepLinkEventDataDecoded = try JSONDecoder().decode(IAFNativeBridgeEvent.DeepLinkEventPayload.self, from: deepLinkEventData)

        #expect(deepLinkEventDataDecoded.ios == url)
    }

    @Test func testDecodeFormAppeared() async throws {
        let json = """
        {
          "type": "formAppeared",
          "data": {
            "formId": "abc123"
          }
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: data)
        #expect(event == .formAppeared)

        // TODO: test that associated values are correct
    }

    @Test func testDecodeTrackProfileEvent() async throws {
        let json = """
        {
          "type": "trackProfileEvent",
          "data": {
            "metric": "Form completed by profile",
            "properties": {
              "form_id": "7uSP7t",
              "form_version_id": 8
            }
          }
        }
        """

        let profileEvent = """
        {
          "metric": "Form completed by profile",
          "properties": {
            "form_id": "7uSP7t",
            "form_version_id": 8
          }
        }
        """
        let jsonData = try #require(json.data(using: .utf8))
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: jsonData)
        guard case let .trackProfileEvent(associatedValueData) = event else {
            Issue.record("event type should be .trackProfileEvent but was '.\(event)'")
            return
        }
        let associatedValueDataDecoded = try JSONDecoder().decode(AnyCodable.self, from: associatedValueData)

        let profileEventData = try #require(profileEvent.data(using: .utf8))
        let profileEventDataDecoded = try JSONDecoder().decode(AnyCodable.self, from: profileEventData)

        #expect(profileEventDataDecoded == associatedValueDataDecoded)
    }

    @Test func testDecodeAggregateEvent() async throws {
        let json = """
        {
          "type": "trackAggregateEvent",
          "data": {
            "metric_group": "signup-forms",
            "events": [
              {
                "metric": "stepSubmit",
                "log_to_statsd": true,
                "log_to_s3": true,
                "log_to_metrics_service": true,
                "metric_service_event_name": "submitted_form_step",
                "event_details": {
                  "form_version_c_id": "1",
                  "is_client": true,
                  "submitted_fields": {
                    "$source": "Local Form",
                    "$email": "local@local.com",
                    "$consent_method": "Klaviyo Form",
                    "$consent_form_id": "64CjgW",
                    "$consent_form_version": 3,
                    "sent_identifiers": {},
                    "sms_consent": true,
                    "$step_name": "Email Opt-In"
                  },
                  "step_name": "Email Opt-In",
                  "step_number": 1,
                  "action_type": "Submit Step",
                  "form_id": "64CjgW",
                  "form_version_id": 3,
                  "form_type": "POPUP",
                  "device_type": "DESKTOP",
                  "hostname": "localhost",
                  "href": "http://localhost:4001/onsite/js/",
                  "page_url": "http://localhost:4001/onsite/js/",
                  "first_referrer": "http://localhost:4001/onsite/js/",
                  "referrer": "http://localhost:4001/onsite/js/",
                  "cid": "ODZjYjJmMjUtNjliMC00ZGVlLTllM2YtNDY5YTlmNjcwYmUz"
                }
              }
            ]
          }
        }
        """

        let aggregateEvent = """
        {
            "metric_group": "signup-forms",
            "events": [
                {
                    "metric": "stepSubmit",
                    "log_to_statsd": true,
                    "log_to_s3": true,
                    "log_to_metrics_service": true,
                    "metric_service_event_name": "submitted_form_step",
                    "event_details": {
                        "form_version_c_id": "1",
                        "is_client": true,
                        "submitted_fields": {
                            "$source": "Local Form",
                            "$email": "local@local.com",
                            "$consent_method": "Klaviyo Form",
                            "$consent_form_id": "64CjgW",
                            "$consent_form_version": 3,
                            "sent_identifiers": {},
                            "sms_consent": true,
                            "$step_name": "Email Opt-In"
                        },
                        "step_name": "Email Opt-In",
                        "step_number": 1,
                        "action_type": "Submit Step",
                        "form_id": "64CjgW",
                        "form_version_id": 3,
                        "form_type": "POPUP",
                        "device_type": "DESKTOP",
                        "hostname": "localhost",
                        "href": "http://localhost:4001/onsite/js/",
                        "page_url": "http://localhost:4001/onsite/js/",
                        "first_referrer": "http://localhost:4001/onsite/js/",
                        "referrer": "http://localhost:4001/onsite/js/",
                        "cid": "ODZjYjJmMjUtNjliMC00ZGVlLTllM2YtNDY5YTlmNjcwYmUz"
                    }
                }
            ]
        }
        """

        let jsonData = try #require(json.data(using: .utf8))
        let aggregateEventData = try #require(aggregateEvent.data(using: .utf8))
        let aggregateEventDataDecoded = try JSONDecoder().decode(AnyCodable.self, from: aggregateEventData)

        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: jsonData)

        guard case let .trackAggregateEvent(associatedValueData) = event else {
            Issue.record("event type should be .trackAggregateEvent but was '.\(event)'")
            return
        }

        let associatedValueDataDecoded = try JSONDecoder().decode(AnyCodable.self, from: associatedValueData)

        #expect(aggregateEventDataDecoded == associatedValueDataDecoded)
    }
}
#endif
