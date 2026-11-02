//
//  PayloadValueTests.swift
//  klaviyo-swift-sdk
//

import KlaviyoFoundation
import XCTest

final class PayloadValueTests: XCTestCase {
    func testDictionaryAcceptsEveryBridgedForm() {
        let swift: [String: Any] = ["a": 1]
        let anyHashable: [AnyHashable: Any] = ["a": 1, 2: "skipped"]
        let objc = NSDictionary(dictionary: ["a": 1])
        XCTAssertEqual(PayloadValue.dictionary(swift)?["a"] as? Int, 1)
        XCTAssertEqual(PayloadValue.dictionary(anyHashable)?["a"] as? Int, 1)
        XCTAssertEqual(PayloadValue.dictionary(anyHashable)?.count, 1, "non-string keys are skipped")
        XCTAssertEqual(PayloadValue.dictionary(objc)?["a"] as? Int, 1)
        XCTAssertNil(PayloadValue.dictionary("not a dictionary"))
        XCTAssertNil(PayloadValue.dictionary(nil))
    }
}
