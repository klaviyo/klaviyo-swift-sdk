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
}
