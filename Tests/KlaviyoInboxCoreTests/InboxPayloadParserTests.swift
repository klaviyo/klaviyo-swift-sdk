//
//  InboxPayloadParserTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxPayloadParserTests {
    private let received = Date(timeIntervalSince1970: 1_800_000_000)
    private let tm = InboxPayloadFixtures.transmissionID

    private func parse(_ json: String) -> InboxRecord? {
        InboxPayloadParser.parse(userInfo: InboxPayloadFixtures.userInfo(json), receivedAt: received)
    }

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    // MARK: Identity and gating

    @Test
    func fullPayloadMapsEveryCoreField() throws {
        let record = try #require(parse(InboxPayloadFixtures.full))
        #expect(record.attribution.transmissionID == tm)
        #expect(record.title == "Sale")
        #expect(record.body == "50% off")
        let home = try url("myapp://home")
        #expect(record.defaultDestination == .deepLink(home))
        let image = try url("https://example.com/i.png")
        #expect(record.mediaURL == image)
        #expect(record.mediaType == "png")
        #expect(record.customData == ["k1": "v1", "n": "2"])
        #expect(record.sentAt == Date(timeIntervalSince1970: 1_791_460_800))
        #expect(record.receivedAt == received)
    }

    @Test
    func payloadWithoutKlaviyoMetadataIsNotParsed() {
        #expect(parse(#"{"aps": {"alert": "hi"}}"#) == nil)
        #expect(!(InboxPayloadParser.hasKlaviyoMetadata(InboxPayloadFixtures.userInfo(#"{"aps": {}}"#))))
    }

    @Test
    func metadataThatIsNotADictionaryIsNotParsedAndDoesNotCrash() {
        // Existing SDK tests use a bare string for `_k`.
        #expect(parse(#"{"body": {"_k": "test_deep_link_regression"}}"#) == nil)
        #expect(!(InboxPayloadParser.hasKlaviyoMetadata(
            InboxPayloadFixtures.userInfo(#"{"body": {"_k": "x"}}"#)
        )))
    }

    @Test
    func missingOrEmptyTransmissionIDIsNotParsedButIsKlaviyoMetadata() {
        #expect(parse(#"{"body": {"_k": {"$flow": "F1"}}}"#) == nil)
        #expect(parse(#"{"body": {"_k": {"tm": ""}}}"#) == nil)
        #expect(InboxPayloadParser.hasKlaviyoMetadata(
            InboxPayloadFixtures.userInfo(#"{"body": {"_k": {"tm": ""}}}"#)
        ))
    }

    @Test
    func numericTransmissionIDIsStringified() {
        #expect(parse(#"{"body": {"_k": {"tm": 12345}}}"#)?.attribution.transmissionID == "12345")
    }

    @Test
    func bodyAsNonDictionaryIsNotParsed() {
        #expect(parse(#"{"body": "plain string"}"#) == nil)
    }

    // MARK: Title and body

    @Test
    func alertAsBareStringBecomesTheBody() throws {
        let record = try #require(parse(InboxPayloadFixtures.minimal(#""aps": {"alert": "Hello"}"#)))
        #expect(record.title == nil)
        #expect(record.body == "Hello")
    }

    @Test
    func missingAlertStillCapturesWithNilTitleAndBody() throws {
        let record = try #require(parse(InboxPayloadFixtures.minimal()))
        #expect(record.title == nil)
        #expect(record.body == nil)
    }

    @Test
    func alertWithLocalizationKeysOnlyKeepsTitleAndBody() throws {
        let alert = #""aps": {"alert": {"title": "T", "loc-key": "K", "loc-args": ["a"]}}"#
        let record = try #require(parse(InboxPayloadFixtures.minimal(alert)))
        #expect(record.title == "T")
        #expect(record.body == nil)
    }

    // MARK: Default destination

    @Test
    func deepLinkUrlWinsOverWebUrl() throws {
        let urls = #""url": "myapp://a", "web_url": "https://b.com""#
        let record = try #require(parse(InboxPayloadFixtures.minimal(urls)))
        let linkA = try url("myapp://a")
        #expect(record.defaultDestination == .deepLink(linkA))
    }

    @Test
    func webUrlIsUsedWhenUrlIsAbsentOrEmpty() throws {
        for members in [#""web_url": "https://b.com""#, #""url": "", "web_url": "https://b.com""#] {
            let record = try #require(parse(InboxPayloadFixtures.minimal(members)))
            let web = try url("https://b.com")
            #expect(record.defaultDestination == .openUrl(web), Comment(rawValue: members))
        }
    }

    @Test
    func disallowedWebUrlSchemeFallsBackToOpenApp() throws {
        for scheme in ["javascript:alert(1)", "file:///etc/passwd", "smsto:123"] {
            let record = try #require(parse(InboxPayloadFixtures.minimal(#""web_url": "\#(scheme)""#)))
            #expect(record.defaultDestination == .openApp, Comment(rawValue: scheme))
        }
    }

    @Test
    func noUrlsMeansOpenApp() throws {
        let minimal = try #require(parse(InboxPayloadFixtures.minimal()))
        #expect(minimal.defaultDestination == .openApp)
    }

    // MARK: Media, custom data, timestamp

    @Test
    func mediaTypeIsNilWhenAbsentAndMediaUrlIsNilWhenAbsent() throws {
        let record = try #require(parse(InboxPayloadFixtures.minimal()))
        #expect(record.mediaURL == nil)
        #expect(record.mediaType == nil)
        let media = InboxPayloadFixtures.minimal(#""rich-media": "https://x.com/a.png""#)
        let withUrl = try #require(parse(media))
        #expect(withUrl.mediaURL != nil)
        #expect(withUrl.mediaType == nil, "no default type is invented")
    }

    @Test
    func customDataStringifiesNestedValuesAndDropsNulls() throws {
        let pairs = #""key_value_pairs": {"s": "v", "n": 3, "o": {"b": 1}, "l": [1, 2], "z": null}"#
        let record = try #require(parse(InboxPayloadFixtures.minimal(pairs)))
        #expect(record.customData == ["s": "v", "n": "3", "o": #"{"b":1}"#, "l": "[1,2]"])
    }

    @Test
    func customDataThatIsNotADictionaryIsEmpty() throws {
        let record = try #require(parse(InboxPayloadFixtures.minimal(#""key_value_pairs": "oops""#)))
        #expect(record.customData.isEmpty)
    }

    @Test
    func unparseableTimestampKeepsTheRecordWithNilSentAt() throws {
        let record = try #require(parse(#"{"body": {"_k": {"tm": "t", "timestamp": "garbage"}}}"#))
        #expect(record.sentAt == nil)
    }

    @Test
    func nonFiniteTimestampKeepsTheRecordWithNilSentAt() throws {
        for value in ["nan", "inf", "-infinity"] {
            let record = try #require(parse(#"{"body": {"_k": {"tm": "t", "timestamp": "\#(value)"}}}"#))
            #expect(record.sentAt == nil, Comment(rawValue: value))
        }
    }

    @Test
    func timestampAcceptsFractionsAndEpochNumbers() throws {
        let base = Date(timeIntervalSince1970: 1_791_460_800)
        let cases: [(String, Date)] = [
            (#""2026-10-08T12:00:00.500Z""#, base.addingTimeInterval(0.5)),
            ("1791460800", base),
            ("1791460800000", base)
        ]
        for (value, expected) in cases {
            let record = try #require(parse(#"{"body": {"_k": {"tm": "t", "timestamp": \#(value)}}}"#))
            #expect(record.sentAt == expected, Comment(rawValue: value))
        }
    }

    @Test
    func receivedAtComesFromTheCallerNotThePayload() throws {
        let full = try #require(parse(InboxPayloadFixtures.full))
        #expect(full.receivedAt == received)
    }

    // MARK: Action buttons

    private func actions(_ buttons: String) throws -> [InboxAction] {
        let json = #"{"body": {"_k": {"tm": "t"}, "action_buttons": \#(buttons)}}"#
        return try #require(parse(json)).actions
    }

    // Which buttons are valid is covered by `ActionButtonParserTests` in `KlaviyoFoundationTests`.
    @Test
    func actionsKeepPayloadOrderAndDropUnknownTypes() throws {
        let record = try #require(parse(InboxPayloadFixtures.full))
        let sale = try url("myapp://sale")
        let web = try url("https://example.com")
        #expect(record.actions == [
            InboxAction(id: "a1", label: "Shop", destination: .deepLink(sale)),
            InboxAction(id: "a3", label: "Web", destination: .openUrl(web))
        ])
    }

    @Test
    func openAppButtonHasNoUrl() throws {
        let parsed = try actions(#"[{"id": "a", "action": "open_app", "label": "Open"}]"#)
        #expect(parsed == [InboxAction(id: "a", label: "Open", destination: .openApp)])
    }

    @Test
    func atMostThreeActionsAreKeptInOrder() throws {
        let buttons = (1...5)
            .map { #"{"id": "\#($0)", "action": "open_app", "label": "B\#($0)"}"# }
            .joined(separator: ",")
        let kept = try actions("[\(buttons)]")
        #expect(kept.map(\.id) == ["1", "2", "3"])
    }

    @Test
    func droppedButtonsDoNotCountTowardTheCap() throws {
        let buttons = """
        [
          {"id": "bad", "action": "deep_link", "label": "x"},
          {"id": "1", "action": "open_app", "label": "x"},
          {"id": "2", "action": "open_app", "label": "x"},
          {"id": "3", "action": "open_app", "label": "x"},
          {"id": "4", "action": "open_app", "label": "x"}
        ]
        """
        let kept = try actions(buttons)
        #expect(kept.map(\.id) == ["1", "2", "3"])
    }

    @Test
    func missingOrNonArrayActionButtonsMeansNoActions() throws {
        let minimal = try #require(parse(InboxPayloadFixtures.minimal()))
        #expect(minimal.actions.isEmpty)
        let notAnArray = try actions(#""oops""#)
        #expect(notAnArray.isEmpty)
        let none = try actions("[]")
        #expect(none.isEmpty)
    }

    // MARK: Badge, transport, raw payload

    @Test
    func fullPayloadBadgeAndTransport() throws {
        let record = try #require(parse(InboxPayloadFixtures.full))
        let expectedBadge = InboxBadge(apsBadge: 3, config: "set_count", value: 5, notificationCount: 7)
        #expect(record.badge == expectedBadge)
        #expect(record.transport == InboxTransportFlags(
            mutableContent: true, contentAvailable: false, priority: "10", sound: "default"
        ))
    }

    @Test
    func noBadgeKeysMeansNilBadgeAndEmptyTransport() throws {
        let record = try #require(parse(InboxPayloadFixtures.minimal()))
        #expect(record.badge == nil)
        #expect(record.transport == InboxTransportFlags())
    }

    @Test
    func eachBadgeKeyAloneProducesABadge() throws {
        let cases: [(String, InboxBadge)] = [
            (#""aps": {"badge": 4}"#, InboxBadge(apsBadge: 4)),
            (#""badge_config": "increment_one""#, InboxBadge(config: "increment_one")),
            (#""badge_value": "8""#, InboxBadge(value: 8)),
            (#""notification_count": 2"#, InboxBadge(notificationCount: 2))
        ]
        for (members, expected) in cases {
            let badge = try #require(parse(InboxPayloadFixtures.minimal(members))).badge
            #expect(badge == expected, Comment(rawValue: members))
        }
    }

    @Test
    func transportFlagsAcceptBooleansAndNumbers() throws {
        let asBools = try #require(parse(InboxPayloadFixtures.minimal(
            #""aps": {"mutable-content": true, "content-available": false}"#
        )))
        #expect(asBools.transport.mutableContent == true)
        #expect(asBools.transport.contentAvailable == false)
        let asNumbers = try #require(parse(InboxPayloadFixtures.minimal(
            #""aps": {"mutable-content": 1, "content-available": 1}"#
        )))
        #expect(asNumbers.transport.mutableContent == true)
        #expect(asNumbers.transport.contentAvailable == true)
    }

    @Test
    func soundThatIsADictionaryIsNotRecordedAsATypedValue() throws {
        let record = try #require(parse(InboxPayloadFixtures.minimal(#""aps": {"sound": {"name": "x"}}"#)))
        #expect(record.transport.sound == nil)
    }

    @Test
    func unmappedKeysAreNotKept() throws {
        let record = try #require(parse(InboxPayloadFixtures.minimal(#""m": "alias", "c": 1, "t": 2"#)))
        #expect(record.sentAt == nil, "the non-normative `t` alias is never read into a typed field")
        let properties = try #require(JSONSerialization.jsonObject(with: record.attribution.rawProperties) as? [String: Any])
        #expect(properties["m"] == nil)
    }

    @Test
    func attributionRawPropertiesDropTheDeviceTokenAndKeepTheRest() throws {
        let record = try #require(parse(InboxPayloadFixtures.full))
        let properties = try #require(JSONSerialization.jsonObject(with: record.attribution.rawProperties) as? [String: Any])
        #expect(properties["pt"] == nil)
        #expect(properties["tm"] as? String == tm)
        #expect(properties["$flow"] as? String == "F1")
    }

    @Test
    func payloadWithUnrepresentableValuesStillParses() throws {
        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": ["tm": "t", "pt": "x"]],
            "weird": [Double.nan, Data([1]), Date(timeIntervalSince1970: 0)],
            7: "non-string key"
        ]
        let record = try #require(InboxPayloadParser.parse(userInfo: userInfo, receivedAt: received))
        let object = try JSONSerialization.jsonObject(with: record.attribution.rawProperties)
        #expect(object as? [String: Any] != nil)
        #expect(record.attribution.transmissionID == "t")
    }
}

#endif
