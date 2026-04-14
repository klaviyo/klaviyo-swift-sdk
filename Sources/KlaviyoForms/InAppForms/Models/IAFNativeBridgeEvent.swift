//
//  IAFNativeBridgeEvent.swift
//  TestApp
//
//  Created by Andrew Balmer on 2/3/25.
//

import Foundation
import OSLog

enum IAFNativeBridgeEvent: Decodable, Equatable {
    case formsDataLoaded
    case formWillAppear(FormWillAppearPayload)
    case formDisappeared(formId: String?, formName: String?)
    case trackProfileEvent(TrackProfileEventPayload)
    case trackAggregateEvent(TrackAggregateEventPayload)
    case openDeepLink(URL?, formId: String?, formName: String?, buttonLabel: String?)
    case abort(String)
    case handShook
    case analyticsEvent
    case lifecycleEvent
    case profileEvent
    case profileMutation

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    private enum TypeIdentifier: String, Decodable {
        case formsDataLoaded
        case formWillAppear
        case formDisappeared
        case trackProfileEvent
        case trackAggregateEvent
        case openDeepLink
        case abort
        case handShook
        case analyticsEvent
        case lifecycleEvent
        case profileEvent
        case profileMutation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeIdentifier = try container.decode(TypeIdentifier.self, forKey: .type)

        switch typeIdentifier {
        case .formsDataLoaded:
            self = .formsDataLoaded
        case .formWillAppear:
            self = try .formWillAppear(container.decode(FormWillAppearPayload.self, forKey: .data))
        case .formDisappeared:
            let payload = try? container.decode(FormContextPayload.self, forKey: .data)
            self = .formDisappeared(formId: payload?.formId, formName: payload?.formName)
        case .trackProfileEvent:
            self = try .trackProfileEvent(container.decode(TrackProfileEventPayload.self, forKey: .data))
        case .trackAggregateEvent:
            self = try .trackAggregateEvent(container.decode(TrackAggregateEventPayload.self, forKey: .data))
        case .openDeepLink:
            let payload = try container.decode(DeepLinkEventPayload.self, forKey: .data)
            self = .openDeepLink(payload.ios, formId: payload.formId, formName: payload.formName, buttonLabel: payload.buttonLabel)
        case .abort:
            let data = try container.decode(AbortPayload.self, forKey: .data)
            self = .abort(data.reason)
        case .handShook:
            self = .handShook
        case .analyticsEvent:
            self = .analyticsEvent
        case .lifecycleEvent:
            self = .lifecycleEvent
        case .profileEvent:
            self = .profileEvent
        case .profileMutation:
            self = .profileMutation
        }
    }
}

extension IAFNativeBridgeEvent {
    struct FormContextPayload: Decodable {
        let formId: String?
        let formName: String?
    }

    struct FormWillAppearPayload: Codable, Equatable {
        let formId: String?
        let formName: String?
        let layout: FormLayout?
    }

    struct TrackProfileEventPayload: Codable, Equatable {
        let metric: String
        let properties: Properties

        struct Properties: Codable, Equatable {
            let formId: String?
            let formVersionId: Int?

            enum CodingKeys: String, CodingKey {
                case formId = "form_id"
                case formVersionId = "form_version_id"
            }
        }

        var eventProperties: [String: Any] {
            var properties: [String: Any] = [:]
            properties["form_id"] = self.properties.formId
            properties["form_version_id"] = self.properties.formVersionId

            return [
                "metric": metric,
                "properties": properties
            ] as [String: Any]
        }
    }

    struct TrackAggregateEventPayload: Codable, Equatable {
        let metricGroup: String
        let events: [TrackedEvent]

        enum CodingKeys: String, CodingKey {
            case metricGroup = "metric_group"
            case events
        }

        struct TrackedEvent: Codable, Equatable {
            let metric: String?
            let logToStatsd: Bool?
            let logToS3: Bool?
            let logToMetricsService: Bool?
            let metricServiceEventName: String?
            let eventDetails: EventDetails?

            enum CodingKeys: String, CodingKey {
                case metric
                case logToStatsd = "log_to_statsd"
                case logToS3 = "log_to_s3"
                case logToMetricsService = "log_to_metrics_service"
                case metricServiceEventName = "metric_service_event_name"
                case eventDetails = "event_details"
            }
        }

        struct EventDetails: Codable, Equatable {
            let formVersionCId: String?
            let isClient: Bool?
            let submittedFields: SubmittedFields?
            let stepName: String?
            let stepNumber: Int?
            let actionType: String?
            let formId: String?
            let formVersionId: Int?
            let formType: String?
            let deviceType: String?
            let hostname: String?
            let href: String?
            let pageURL: String?
            let firstReferrer: String?
            let referrer: String?
            let cid: String?

            enum CodingKeys: String, CodingKey {
                case formVersionCId = "form_version_c_id"
                case isClient = "is_client"
                case submittedFields = "submitted_fields"
                case stepName = "step_name"
                case stepNumber = "step_number"
                case actionType = "action_type"
                case formId = "form_id"
                case formVersionId = "form_version_id"
                case formType = "form_type"
                case deviceType = "device_type"
                case hostname
                case href
                case pageURL = "page_url"
                case firstReferrer = "first_referrer"
                case referrer
                case cid
            }
        }

        struct SubmittedFields: Codable, Equatable {
            let source: String?
            let email: String?
            let consentMethod: String?
            let consentFormId: String?
            let consentFormVersion: Int?
            let sentIdentifiers: [String: String]?
            let smsConsent: Bool?
            let stepName: String?

            enum CodingKeys: String, CodingKey {
                case source = "$source"
                case email = "$email"
                case consentMethod = "$consent_method"
                case consentFormId = "$consent_form_id"
                case consentFormVersion = "$consent_form_version"
                case sentIdentifiers = "sent_identifiers"
                case smsConsent = "sms_consent"
                case stepName = "$step_name"
            }
        }
    }

    struct DeepLinkEventPayload: Decodable {
        let ios: URL?
        let formId: String?
        let formName: String?
        let buttonLabel: String?

        enum CodingKeys: String, CodingKey {
            case ios
            case formId
            case formName
            case buttonLabel
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            formId = try container.decodeIfPresent(String.self, forKey: .formId)
            formName = try container.decodeIfPresent(String.self, forKey: .formName)
            buttonLabel = try container.decodeIfPresent(String.self, forKey: .buttonLabel)
            // Handle missing, null, or empty string gracefully
            guard let urlString = try container.decodeIfPresent(String.self, forKey: .ios),
                  !urlString.isEmpty else {
                ios = nil
                return
            }
            ios = URL(string: urlString)
        }
    }

    struct AbortPayload: Decodable {
        let reason: String
    }
}

extension IAFNativeBridgeEvent {
    public static var handshake: String {
        struct HandshakeData: Codable {
            var type: String
            var version: Int
        }

        let handshakeArray = handshakeEvents.map { event -> HandshakeData in
            HandshakeData(type: event.name, version: event.version)
        }

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(handshakeArray)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error encoding handshake data: \(error)")
            }
        }
        return ""
    }

    private static var handshakeEvents: [IAFNativeBridgeEvent] {
        // events that JS is permitted to sending
        [
            .formWillAppear(FormWillAppearPayload(formId: nil, formName: nil, layout: nil)),
            .formDisappeared(formId: nil, formName: nil),
            .trackProfileEvent(
                TrackProfileEventPayload(
                    metric: "",
                    properties: .init(formId: "", formVersionId: 0)
                )
            ),
            .trackAggregateEvent(
                TrackAggregateEventPayload(
                    metricGroup: "",
                    events: [
                        .init(
                            metric: "",
                            logToStatsd: false,
                            logToS3: false,
                            logToMetricsService: false,
                            metricServiceEventName: "",
                            eventDetails: .init(
                                formVersionCId: "",
                                isClient: false,
                                submittedFields: .init(
                                    source: "",
                                    email: "",
                                    consentMethod: "",
                                    consentFormId: "",
                                    consentFormVersion: 0,
                                    sentIdentifiers: [:],
                                    smsConsent: false,
                                    stepName: ""
                                ),
                                stepName: "",
                                stepNumber: 0,
                                actionType: "",
                                formId: "",
                                formVersionId: 0,
                                formType: "",
                                deviceType: "",
                                hostname: "",
                                href: "",
                                pageURL: "",
                                firstReferrer: "",
                                referrer: "",
                                cid: ""
                            )
                        )
                    ]
                )
            ),
            .openDeepLink(URL(string: "https://example.com")!, formId: nil, formName: nil, buttonLabel: nil),
            .abort(""),
            .lifecycleEvent,
            .profileEvent,
            .profileMutation
        ]
    }

    private var version: Int {
        switch self {
        case .formsDataLoaded: return 1
        case .formWillAppear: return 2
        case .formDisappeared: return 1
        case .trackProfileEvent: return 1
        case .trackAggregateEvent: return 1
        case .openDeepLink: return 2
        case .abort: return 1
        case .handShook: return 1
        case .analyticsEvent: return 1
        case .lifecycleEvent: return 1
        case .profileEvent: return 1
        case .profileMutation: return 1
        }
    }

    private var name: String {
        switch self {
        case .formsDataLoaded: return "formsDataLoaded"
        case .formWillAppear: return "formWillAppear"
        case .formDisappeared: return "formDisappeared"
        case .trackProfileEvent: return "trackProfileEvent"
        case .trackAggregateEvent: return "trackAggregateEvent"
        case .openDeepLink: return "openDeepLink"
        case .abort: return "abort"
        case .handShook: return "handShook"
        case .analyticsEvent: return "analyticsEvent"
        case .lifecycleEvent: return "lifecycleEvent"
        case .profileEvent: return "profileEvent"
        case .profileMutation: return "profileMutation"
        }
    }
}
