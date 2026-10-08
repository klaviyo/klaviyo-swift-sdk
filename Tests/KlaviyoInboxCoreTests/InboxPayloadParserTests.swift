//
//  InboxPayloadParserTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class InboxPayloadParserTests: XCTestCase {
    private let received = Date(timeIntervalSince1970: 1_800_000_000)
    private let tm = InboxPayloadFixtures.transmissionID

    private func parse(_ json: String) -> InboxRecord? {
        InboxPayloadParser.parse(userInfo: InboxPayloadFixtures.userInfo(json), receivedAt: received)
    }

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    // MARK: Identity and gating

    func testFullPayloadMapsEveryCoreField() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.full))
        XCTAssertEqual(record.attribution.transmissionID, tm)
        XCTAssertEqual(record.title, "Sale")
        XCTAssertEqual(record.body, "50% off")
        XCTAssertEqual(record.defaultDestination, try .deepLink(url("myapp://home")))
        XCTAssertEqual(record.mediaURL, try url("https://example.com/i.png"))
        XCTAssertEqual(record.mediaType, "png")
        XCTAssertEqual(record.customData, ["k1": "v1", "n": "2"])
        XCTAssertEqual(record.sentAt, Date(timeIntervalSince1970: 1_791_460_800))
        XCTAssertEqual(record.receivedAt, received)
    }

    func testPayloadWithoutKlaviyoMetadataIsNotParsed() {
        XCTAssertNil(parse(#"{"aps": {"alert": "hi"}}"#))
        XCTAssertFalse(InboxPayloadParser.hasKlaviyoMetadata(InboxPayloadFixtures.userInfo(#"{"aps": {}}"#)))
    }

    func testMetadataThatIsNotADictionaryIsNotParsedAndDoesNotCrash() {
        // Existing SDK tests use a bare string for `_k`.
        XCTAssertNil(parse(#"{"body": {"_k": "test_deep_link_regression"}}"#))
        XCTAssertFalse(InboxPayloadParser.hasKlaviyoMetadata(
            InboxPayloadFixtures.userInfo(#"{"body": {"_k": "x"}}"#)
        ))
    }

    func testMissingOrEmptyTransmissionIDIsNotParsedButIsKlaviyoMetadata() {
        XCTAssertNil(parse(#"{"body": {"_k": {"$flow": "F1"}}}"#))
        XCTAssertNil(parse(#"{"body": {"_k": {"tm": ""}}}"#))
        XCTAssertTrue(InboxPayloadParser.hasKlaviyoMetadata(
            InboxPayloadFixtures.userInfo(#"{"body": {"_k": {"tm": ""}}}"#)
        ))
    }

    func testNumericTransmissionIDIsStringified() {
        XCTAssertEqual(parse(#"{"body": {"_k": {"tm": 12345}}}"#)?.attribution.transmissionID, "12345")
    }

    func testBodyAsNonDictionaryIsNotParsed() {
        XCTAssertNil(parse(#"{"body": "plain string"}"#))
    }

    // MARK: Title and body

    func testAlertAsBareStringBecomesTheBody() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(#""aps": {"alert": "Hello"}"#)))
        XCTAssertNil(record.title)
        XCTAssertEqual(record.body, "Hello")
    }

    func testMissingAlertStillCapturesWithNilTitleAndBody() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal()))
        XCTAssertNil(record.title)
        XCTAssertNil(record.body)
    }

    func testAlertWithLocalizationKeysOnlyKeepsTitleAndBody() throws {
        let alert = #""aps": {"alert": {"title": "T", "loc-key": "K", "loc-args": ["a"]}}"#
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(alert)))
        XCTAssertEqual(record.title, "T")
        XCTAssertNil(record.body)
    }

    // MARK: Default destination

    func testDeepLinkUrlWinsOverWebUrl() throws {
        let urls = #""url": "myapp://a", "web_url": "https://b.com""#
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(urls)))
        XCTAssertEqual(record.defaultDestination, try .deepLink(url("myapp://a")))
    }

    func testWebUrlIsUsedWhenUrlIsAbsentOrEmpty() throws {
        for members in [#""web_url": "https://b.com""#, #""url": "", "web_url": "https://b.com""#] {
            let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(members)))
            XCTAssertEqual(record.defaultDestination, try .openUrl(url("https://b.com")), members)
        }
    }

    func testDisallowedWebUrlSchemeFallsBackToOpenApp() throws {
        for scheme in ["javascript:alert(1)", "file:///etc/passwd", "smsto:123"] {
            let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(#""web_url": "\#(scheme)""#)))
            XCTAssertEqual(record.defaultDestination, .openApp, scheme)
        }
    }

    func testNoUrlsMeansOpenApp() throws {
        XCTAssertEqual(try XCTUnwrap(parse(InboxPayloadFixtures.minimal())).defaultDestination, .openApp)
    }

    // MARK: Media, custom data, timestamp

    func testMediaTypeIsNilWhenAbsentAndMediaUrlIsNilWhenAbsent() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal()))
        XCTAssertNil(record.mediaURL)
        XCTAssertNil(record.mediaType)
        let media = InboxPayloadFixtures.minimal(#""rich-media": "https://x.com/a.png""#)
        let withUrl = try XCTUnwrap(parse(media))
        XCTAssertNotNil(withUrl.mediaURL)
        XCTAssertNil(withUrl.mediaType, "no default type is invented")
    }

    func testCustomDataStringifiesNestedValuesAndDropsNulls() throws {
        let pairs = #""key_value_pairs": {"s": "v", "n": 3, "o": {"b": 1}, "l": [1, 2], "z": null}"#
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(pairs)))
        XCTAssertEqual(record.customData, ["s": "v", "n": "3", "o": #"{"b":1}"#, "l": "[1,2]"])
    }

    func testCustomDataThatIsNotADictionaryIsEmpty() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(#""key_value_pairs": "oops""#)))
        XCTAssertTrue(record.customData.isEmpty)
    }

    func testUnparseableTimestampKeepsTheRecordWithNilSentAt() throws {
        let record = try XCTUnwrap(parse(#"{"body": {"_k": {"tm": "t", "timestamp": "garbage"}}}"#))
        XCTAssertNil(record.sentAt)
    }

    func testTimestampAcceptsFractionsAndEpochNumbers() throws {
        let base = Date(timeIntervalSince1970: 1_791_460_800)
        let cases: [(String, Date)] = [
            (#""2026-10-08T12:00:00.500Z""#, base.addingTimeInterval(0.5)),
            ("1791460800", base),
            ("1791460800000", base)
        ]
        for (value, expected) in cases {
            let record = try XCTUnwrap(parse(#"{"body": {"_k": {"tm": "t", "timestamp": \#(value)}}}"#))
            XCTAssertEqual(record.sentAt, expected, value)
        }
    }

    func testReceivedAtComesFromTheCallerNotThePayload() throws {
        XCTAssertEqual(try XCTUnwrap(parse(InboxPayloadFixtures.full)).receivedAt, received)
    }

    // MARK: Action buttons

    private func actions(_ buttons: String) throws -> [InboxAction] {
        let json = #"{"body": {"_k": {"tm": "t"}, "action_buttons": \#(buttons)}}"#
        return try XCTUnwrap(parse(json)).actions
    }

    func testActionsKeepPayloadOrderAndUnknownTypesInPlace() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.full))
        XCTAssertEqual(record.actions, [
            try InboxAction(id: "a1", label: "Shop", destination: .deepLink(url("myapp://sale"))),
            InboxAction(id: "a2", label: "Later", destination: .unknown("snooze")),
            try InboxAction(id: "a3", label: "Web", destination: .openUrl(url("https://example.com")))
        ])
    }

    func testOpenAppButtonHasNoUrl() throws {
        XCTAssertEqual(
            try actions(#"[{"id": "a", "action": "open_app", "label": "Open"}]"#),
            [InboxAction(id: "a", label: "Open", destination: .openApp)]
        )
    }

    func testNullUrlIsTreatedAsAbsent() throws {
        XCTAssertEqual(
            try actions(#"[{"id": "a", "action": "open_app", "label": "Open", "url": null}]"#).count,
            1
        )
    }

    func testKnownActionsWithInvalidUrlCombinationsAreDropped() throws {
        let buttons = """
        [
          {"id": "1", "action": "open_app", "label": "x", "url": "myapp://nope"},
          {"id": "2", "action": "deep_link", "label": "x"},
          {"id": "3", "action": "open_url", "label": "x"},
          {"id": "4", "action": "open_url", "label": "x", "url": "javascript:alert(1)"},
          {"id": "5", "action": "open_url", "label": "x", "url": "smsto:123"},
          {"id": "6", "action": "open_app", "label": "kept"}
        ]
        """
        XCTAssertEqual(try actions(buttons).map(\.id), ["6"])
    }

    func testMalformedEntriesAreSkippedWithoutDroppingNeighbours() throws {
        let buttons = """
        [
          "not a dictionary",
          null,
          {"id": "", "action": "open_app", "label": "empty id"},
          {"id": "x", "action": "open_app", "label": ""},
          {"id": "y", "label": "no action"},
          {"label": "no id", "action": "open_app"},
          {"id": "ok", "action": "open_app", "label": "Fine"}
        ]
        """
        XCTAssertEqual(try actions(buttons).map(\.id), ["ok"])
    }

    func testAtMostThreeActionsAreKeptInOrder() throws {
        let buttons = (1...5)
            .map { #"{"id": "\#($0)", "action": "open_app", "label": "B\#($0)"}"# }
            .joined(separator: ",")
        XCTAssertEqual(try actions("[\(buttons)]").map(\.id), ["1", "2", "3"])
    }

    func testDroppedButtonsDoNotCountTowardTheCap() throws {
        let buttons = """
        [
          {"id": "bad", "action": "deep_link", "label": "x"},
          {"id": "1", "action": "open_app", "label": "x"},
          {"id": "2", "action": "open_app", "label": "x"},
          {"id": "3", "action": "open_app", "label": "x"},
          {"id": "4", "action": "open_app", "label": "x"}
        ]
        """
        XCTAssertEqual(try actions(buttons).map(\.id), ["1", "2", "3"])
    }

    func testMissingOrNonArrayActionButtonsMeansNoActions() throws {
        XCTAssertTrue(try XCTUnwrap(parse(InboxPayloadFixtures.minimal())).actions.isEmpty)
        XCTAssertTrue(try actions(#""oops""#).isEmpty)
        XCTAssertTrue(try actions("[]").isEmpty)
    }

    // MARK: Badge, transport, raw payload

    func testFullPayloadBadgeAndTransport() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.full))
        let expectedBadge = InboxBadge(apsBadge: 3, config: "set_count", value: 5, notificationCount: 7)
        XCTAssertEqual(record.badge, expectedBadge)
        XCTAssertEqual(
            record.transport,
            InboxTransportFlags(
                mutableContent: true, contentAvailable: false, priority: "10", sound: "default"
            )
        )
    }

    func testNoBadgeKeysMeansNilBadgeAndEmptyTransport() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal()))
        XCTAssertNil(record.badge)
        XCTAssertEqual(record.transport, InboxTransportFlags())
    }

    func testEachBadgeKeyAloneProducesABadge() throws {
        let cases: [(String, InboxBadge)] = [
            (#""aps": {"badge": 4}"#, InboxBadge(apsBadge: 4)),
            (#""badge_config": "increment_one""#, InboxBadge(config: "increment_one")),
            (#""badge_value": "8""#, InboxBadge(value: 8)),
            (#""notification_count": 2"#, InboxBadge(notificationCount: 2))
        ]
        for (members, expected) in cases {
            let badge = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(members))).badge
            XCTAssertEqual(badge, expected, members)
        }
    }

    func testTransportFlagsAcceptBooleansAndNumbers() throws {
        let asBools = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(
            #""aps": {"mutable-content": true, "content-available": false}"#
        )))
        XCTAssertEqual(asBools.transport.mutableContent, true)
        XCTAssertEqual(asBools.transport.contentAvailable, false)
        let asNumbers = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(
            #""aps": {"mutable-content": 1, "content-available": 1}"#
        )))
        XCTAssertEqual(asNumbers.transport.mutableContent, true)
        XCTAssertEqual(asNumbers.transport.contentAvailable, true)
    }

    func testSoundThatIsADictionaryIsNotRecordedAsATypedValue() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(#""aps": {"sound": {"name": "x"}}"#)))
        XCTAssertNil(record.transport.sound)
    }

    func testRawPayloadKeepsEverythingExceptTheDeviceToken() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.full))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: record.rawPayload) as? [String: Any])
        let body = try XCTUnwrap(raw["body"] as? [String: Any])
        let metadata = try XCTUnwrap(body["_k"] as? [String: Any])
        XCTAssertNil(metadata["pt"])
        XCTAssertEqual(metadata["$flow"] as? String, "F1")
        XCTAssertEqual(raw["priority"] as? String, "10")
        XCTAssertNotNil(raw["aps"])
        let buttons = body["action_buttons"] as? [Any]
        XCTAssertEqual(buttons?.count, 3, "unmapped buttons survive in the raw payload")
    }

    func testUnmappedAliasesSurviveOnlyInTheRawPayload() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.minimal(#""m": "alias", "c": 1, "t": 2"#)))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: record.rawPayload) as? [String: Any])
        XCTAssertEqual(raw["m"] as? String, "alias")
        XCTAssertNil(record.sentAt, "the non-normative `t` alias is never read into a typed field")
    }

    func testAttributionRawPropertiesDropTheDeviceTokenAndKeepTheRest() throws {
        let record = try XCTUnwrap(parse(InboxPayloadFixtures.full))
        let properties = try XCTUnwrap(
            JSONSerialization.jsonObject(with: record.attribution.rawProperties) as? [String: Any]
        )
        XCTAssertNil(properties["pt"])
        XCTAssertEqual(properties["tm"] as? String, tm)
        XCTAssertEqual(properties["$flow"] as? String, "F1")
    }

    func testPayloadWithUnrepresentableValuesStillParses() throws {
        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": ["tm": "t", "pt": "x"]],
            "weird": [Double.nan, Data([1]), Date(timeIntervalSince1970: 0)],
            7: "non-string key"
        ]
        let record = try XCTUnwrap(InboxPayloadParser.parse(userInfo: userInfo, receivedAt: received))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: record.rawPayload) as? [String: Any])
        XCTAssertEqual(record.attribution.transmissionID, "t")
    }
}
