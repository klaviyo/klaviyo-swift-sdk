//
//  FormLayoutTests.swift
//  klaviyo-swift-sdk
//
//  Created by Evan Masseau on 4/22/26.
//

@testable import KlaviyoForms
import UIKit
import XCTest

final class FormLayoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        #if DEBUG
        FormLayoutTestHooks.resetDeprecationLogger()
        #endif
    }

    // MARK: - Decoding: offsets / margin wire key

    func testDecodesOffsetsKey() throws {
        let jsonString = """
        {
            "position": "BOTTOM",
            "width":  { "value": 100, "unit": "PERCENT" },
            "height": { "value": 200, "unit": "FIXED" },
            "offsets": { "top": 1, "bottom": 2, "left": 3, "right": 4 }
        }
        """

        let layout = try JSONDecoder().decode(FormLayout.self, from: Data(jsonString.utf8))
        XCTAssertEqual(layout.offsets, Offsets(top: 1, bottom: 2, left: 3, right: 4))
        XCTAssertTrue(
            layout.addSafeAreaInsetsToOffsets,
            "addSafeAreaInsetsToOffsets should default to true when absent"
        )
    }

    func testFallsBackToMarginKeyWhenOffsetsMissing() throws {
        let jsonString = """
        {
            "position": "TOP",
            "width":  { "value": 100, "unit": "PERCENT" },
            "height": { "value": 100, "unit": "PERCENT" },
            "margin": { "top": 5, "bottom": 6, "left": 7, "right": 8 }
        }
        """

        let layout = try JSONDecoder().decode(FormLayout.self, from: Data(jsonString.utf8))
        XCTAssertEqual(layout.offsets, Offsets(top: 5, bottom: 6, left: 7, right: 8))
    }

    func testOffsetsWinsWhenBothKeysPresent() throws {
        let jsonString = """
        {
            "position": "CENTER",
            "width":  { "value": 100, "unit": "PERCENT" },
            "height": { "value": 100, "unit": "PERCENT" },
            "offsets": { "top": 10, "bottom": 10, "left": 10, "right": 10 },
            "margin":  { "top": 99, "bottom": 99, "left": 99, "right": 99 }
        }
        """

        let layout = try JSONDecoder().decode(FormLayout.self, from: Data(jsonString.utf8))
        XCTAssertEqual(layout.offsets, Offsets(top: 10, bottom: 10, left: 10, right: 10))
    }

    func testDefaultsOffsetsToZeroWhenBothKeysAbsent() throws {
        let jsonString = """
        {
            "position": "FULLSCREEN"
        }
        """

        let layout = try JSONDecoder().decode(FormLayout.self, from: Data(jsonString.utf8))
        XCTAssertEqual(layout.offsets, .zero)
    }

    // MARK: - Decoding: addSafeAreaInsetsToOffsets

    func testAddSafeAreaInsetsToOffsetsDefaultsToTrue() throws {
        let jsonString = """
        {
            "position": "BOTTOM",
            "offsets": { "top": 0, "bottom": 0, "left": 0, "right": 0 }
        }
        """

        let layout = try JSONDecoder().decode(FormLayout.self, from: Data(jsonString.utf8))
        XCTAssertTrue(layout.addSafeAreaInsetsToOffsets)
    }

    func testAddSafeAreaInsetsToOffsetsParsesFalse() throws {
        let jsonString = """
        {
            "position": "BOTTOM",
            "offsets": { "top": 0, "bottom": 0, "left": 0, "right": 0 },
            "addSafeAreaInsetsToOffsets": false
        }
        """

        let layout = try JSONDecoder().decode(FormLayout.self, from: Data(jsonString.utf8))
        XCTAssertFalse(layout.addSafeAreaInsetsToOffsets)
    }

    func testAddSafeAreaInsetsToOffsetsParsesTrueExplicitly() throws {
        let jsonString = """
        {
            "position": "BOTTOM",
            "addSafeAreaInsetsToOffsets": true
        }
        """

        let layout = try JSONDecoder().decode(FormLayout.self, from: Data(jsonString.utf8))
        XCTAssertTrue(layout.addSafeAreaInsetsToOffsets)
    }
}
