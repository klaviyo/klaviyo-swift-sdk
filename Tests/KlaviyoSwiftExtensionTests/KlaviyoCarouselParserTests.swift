//
//  KlaviyoCarouselParserTests.swift
//

@testable import KlaviyoSwiftExtension
import Foundation
import XCTest

class KlaviyoCarouselParserTests: XCTestCase {
    private func card(
        image: Any? = "https://cdn.example.com/card.jpg",
        action: Any? = "deep_link",
        url: Any? = "myapp://card",
        title: Any? = nil,
        description: Any? = nil
    ) -> [String: Any] {
        var card: [String: Any] = [:]
        card["image_url"] = image
        card["action"] = action
        card["url"] = url
        card["title"] = title
        card["description"] = description
        return card
    }

    private func userInfo(_ cards: [Any]) -> [AnyHashable: Any] {
        ["body": ["_k": [:], "carousel_cards": cards]]
    }

    // MARK: - Card count

    func testParseCards_ReturnsNilWithoutCarouselCards() {
        XCTAssertNil(KlaviyoCarouselParser.parseCards(from: ["body": ["_k": [:]]]))
        XCTAssertFalse(KlaviyoCarouselParser.hasCarouselCards(["body": ["_k": [:]]]))
    }

    func testParseCards_AcceptsTwoToFiveCards() {
        for count in 2...5 {
            let result = KlaviyoCarouselParser.parseCards(from: userInfo(Array(repeating: card(), count: count)))
            XCTAssertEqual(result?.count, count)
        }
    }

    func testParseCards_ReturnsNilOutsideTwoToFiveCards() {
        for count in [0, 1, 6] {
            let payload = userInfo(Array(repeating: card(), count: count))
            XCTAssertTrue(KlaviyoCarouselParser.hasCarouselCards(payload))
            XCTAssertNil(KlaviyoCarouselParser.parseCards(from: payload), "\(count) cards should fall back")
        }
    }

    func testParseCards_CountsOnlyValidCardsTowardTheMinimum() {
        XCTAssertNil(KlaviyoCarouselParser.parseCards(from: userInfo([card(), card(image: nil)])))
    }

    // MARK: - Position

    func testParseCards_PositionIsOriginalIndexBeforeInvalidCardsAreDropped() {
        let result = KlaviyoCarouselParser.parseCards(from: userInfo([card(), card(image: nil), card(), "not a card"]))
        XCTAssertEqual(result?.map(\.position), [1, 3])
    }

    func testParseCards_IgnoresPositionKey() {
        var positioned = card()
        positioned["position"] = 9
        XCTAssertEqual(KlaviyoCarouselParser.parseCards(from: userInfo([positioned, card()]))?.map(\.position), [1, 2])
    }

    // MARK: - Fields

    func testParseCards_ReadsFieldsAndTreatsBlankTextAsAbsent() {
        let result = KlaviyoCarouselParser.parseCards(from: userInfo([
            card(title: "Sale", description: "Up to 50% off"),
            card(title: "  ", description: "")
        ]))
        XCTAssertEqual(result?.first, CarouselCardDefinition(
            position: 1,
            imageURL: URL(string: "https://cdn.example.com/card.jpg")!,
            title: "Sale",
            description: "Up to 50% off",
            action: .deepLink,
            url: "myapp://card"
        ))
        XCTAssertNil(result?.last?.title)
        XCTAssertNil(result?.last?.description)
    }

    // MARK: - Image URL

    func testParseCards_SkipsInvalidImageURLs() {
        let invalidImages: [Any?] = [nil, "", 42, "file:///tmp/card.jpg", "ftp://example.com/card.jpg", "https:///card.jpg"]
        for image in invalidImages {
            let result = KlaviyoCarouselParser.parseCards(from: userInfo([card(), card(), card(image: image)]))
            XCTAssertEqual(result?.count, 2, "image_url \(String(describing: image)) should be skipped")
        }
    }

    func testParseCards_AcceptsHTTPImages() {
        XCTAssertEqual(
            KlaviyoCarouselParser.parseCards(from: userInfo([card(image: "http://example.com/a.png"), card()]))?.count,
            2
        )
    }

    // MARK: - Action and URL

    func testParseCards_ValidActionURLCombinations() {
        let result = KlaviyoCarouselParser.parseCards(from: userInfo([
            card(action: "open_app", url: nil),
            card(action: "deep_link", url: "myapp://sale"),
            card(action: "open_url", url: "https://www.klaviyo.com")
        ]))
        XCTAssertEqual(result?.map(\.action), [.openApp, .deepLink, .openUrl])
    }

    func testParseCards_OpenAppTreatsBlankOrNullURLAsAbsent() {
        let result = KlaviyoCarouselParser.parseCards(from: userInfo([
            card(action: "open_app", url: ""),
            card(action: "open_app", url: NSNull())
        ]))
        XCTAssertEqual(result?.map(\.action), [.openApp, .openApp])
        XCTAssertEqual(result?.compactMap(\.url), [])
    }

    func testParseCards_SkipsInvalidActionURLCombinations() {
        let invalidCards = [
            card(action: nil),
            card(action: "dismiss"),
            card(action: "open_app", url: "myapp://sale"),
            card(action: "deep_link", url: nil),
            card(action: "open_url", url: nil),
            card(action: "open_url", url: "javascript:alert(1)"),
            card(action: "open_app", url: 42)
        ]
        for invalid in invalidCards {
            let result = KlaviyoCarouselParser.parseCards(from: userInfo([card(), card(), invalid]))
            XCTAssertEqual(result?.count, 2, "\(invalid) should be skipped")
        }
    }
}
