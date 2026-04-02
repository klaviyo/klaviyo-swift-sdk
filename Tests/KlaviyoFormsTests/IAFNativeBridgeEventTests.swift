//
//  IAFNativeBridgeEventTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/3/25.
//

@testable import KlaviyoForms
import Foundation

#if canImport(Testing)
import Testing

struct IAFNativeBridgeEventTests {
    @Test
    func testHandshakeCreated() async throws {
        struct TestableHandshakeData: Codable, Equatable {
            var type: String
            var version: Int
        }
        let expectedHandshake = """
        [{"type":"formWillAppear","version":1},{"type":"formDisappeared","version":1},{"type":"trackProfileEvent","version":1},{"type":"trackAggregateEvent","version":1},{"type":"openDeepLink","version":2},{"type":"abort","version":1},{"type":"lifecycleEvent","version":1},{"type":"profileEvent","version":1},{"type":"profileMutation","version":1}]
        """
        let expectedData = try #require(expectedHandshake.data(using: .utf8))
        let expectedHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: expectedData)

        let actualHandshake = IAFNativeBridgeEvent.handshake
        let actualData = try #require(actualHandshake.data(using: .utf8))
        let actualHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: actualData)
        #expect(actualHandshakeData == expectedHandshakeData)
    }

    @Test
    func testHandShook() async throws {
        let json = """
        {
          "type": "handShook",
          "data": {}
        }
        """

        let data = try #require(json.data(using: .utf8))
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: data)
        #expect(event == .handShook)
    }

    @Test
    func testAbort() async throws {
        let json = """
        {
          "type": "abort",
          "data": {
            "reason": "because"
          }
        }
        """

        let data = try #require(json.data(using: .utf8))
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: data)
        guard case let .abort(reason) = event else {
            Issue.record("event type should be .abort but was '.\(event)'")
            return
        }

        #expect(reason == "because")
    }

    @Test
    func testDecodeOpenDeepLink() async throws {
        let json = """
        {
          "type": "openDeepLink",
          "data": {
            "ios": "klaviyotest://settings",
            "android": "klaviyotest://settings"
          }
        }
        """

        let data = try #require(json.data(using: .utf8))
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: data)
        guard case let .openDeepLink(url) = event else {
            Issue.record("event type should be .openDeepLink but was '.\(event)'")
            return
        }

        let expectedUrl = try #require(URL(string: "klaviyotest://settings"))
        #expect(url == expectedUrl)
    }

    @Test
    func testDecodeFormWillAppear() async throws {
        let json = """
        {
          "type": "formWillAppear",
          "data": {
            "formId": "abc123",
            "formName": "Test Form"
          }
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: data)
        guard case let .formWillAppear(payload) = event else {
            Issue.record("event type should be .formWillAppear but was '.\(event)'")
            return
        }
        #expect(payload.formId == "abc123")
        #expect(payload.formName == "Test Form")
    }

    @Test
    func testDecodeFormWillAppearWithoutFormName() async throws {
        let json = """
        {
          "type": "formWillAppear",
          "data": {
            "formId": "abc123"
          }
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: data)
        guard case let .formWillAppear(payload) = event else {
            Issue.record("event type should be .formWillAppear but was '.\(event)'")
            return
        }
        #expect(payload.formId == "abc123")
        #expect(payload.formName == nil)
    }

    @Test
    func testDecodeFormDisappeared() async throws {
        let json = """
        {
          "type": "formDisappeared",
          "data": {
            "formId": "abc123"
          }
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: data)
        #expect(event == .formDisappeared)
    }

    @Test
    func testDecodeTrackProfileEvent() async throws {
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

        let jsonData = try #require(json.data(using: .utf8))
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: jsonData)
        guard case let .trackProfileEvent(payload) = event else {
            Issue.record("event type should be .trackProfileEvent but was '.\(event)'")
            return
        }

        #expect(payload.metric == "Form completed by profile")
        #expect(payload.properties.formId == "7uSP7t")
        #expect(payload.properties.formVersionId == 8)
    }

    @Test
    func testDecodeAggregateEvent() async throws {
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

        let jsonData = try #require(json.data(using: .utf8))
        let event = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: jsonData)

        guard case let .trackAggregateEvent(payload) = event else {
            Issue.record("event type should be .trackAggregateEvent but was '.\(event)'")
            return
        }

        #expect(payload.metricGroup == "signup-forms")
        #expect(payload.events.count == 1)

        let firstEvent = try #require(payload.events.first)
        #expect(firstEvent.metric == "stepSubmit")
        #expect(firstEvent.logToStatsd == true)
        #expect(firstEvent.logToS3 == true)
        #expect(firstEvent.logToMetricsService == true)
        #expect(firstEvent.metricServiceEventName == "submitted_form_step")

        let details = try #require(firstEvent.eventDetails)
        #expect(details.formVersionCId == "1")
        #expect(details.isClient == true)
        #expect(details.stepName == "Email Opt-In")
        #expect(details.stepNumber == 1)
        #expect(details.actionType == "Submit Step")
        #expect(details.formId == "64CjgW")
        #expect(details.formVersionId == 3)
        #expect(details.formType == "POPUP")
        #expect(details.deviceType == "DESKTOP")
        #expect(details.hostname == "localhost")
        #expect(details.href == "http://localhost:4001/onsite/js/")
        #expect(details.pageURL == "http://localhost:4001/onsite/js/")
        #expect(details.firstReferrer == "http://localhost:4001/onsite/js/")
        #expect(details.referrer == "http://localhost:4001/onsite/js/")
        #expect(details.cid == "ODZjYjJmMjUtNjliMC00ZGVlLTllM2YtNDY5YTlmNjcwYmUz")

        let submittedFields = try #require(details.submittedFields)
        #expect(submittedFields.source == "Local Form")
        #expect(submittedFields.email == "local@local.com")
        #expect(submittedFields.consentMethod == "Klaviyo Form")
        #expect(submittedFields.consentFormId == "64CjgW")
        #expect(submittedFields.consentFormVersion == 3)
        #expect(submittedFields.sentIdentifiers == [:])
        #expect(submittedFields.smsConsent == true)
        #expect(submittedFields.stepName == "Email Opt-In")
    }
}
#endif
