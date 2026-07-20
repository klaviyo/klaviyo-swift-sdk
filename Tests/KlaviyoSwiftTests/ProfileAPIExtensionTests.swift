//
//  ProfileAPIExtensionTests.swift
//
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

final class ProfileAPIExtensionTests: XCTestCase {
    private var warnings: [String] = []

    override func setUp() {
        super.setUp()
        warnings = []
        environment = KlaviyoEnvironment.test()
        environment.emitDeveloperWarning = { [weak self] in self?.warnings.append($0) }
    }

    func testDifferentNonEmptyValueReturnsTrueWithoutWarning() {
        XCTAssertTrue("new@example.com".isNotEmptyOrSame(as: "old@example.com", identifier: "email"))
        XCTAssertTrue(warnings.isEmpty)
    }

    func testValueAgainstNilStateReturnsTrue() {
        XCTAssertTrue("new@example.com".isNotEmptyOrSame(as: nil, identifier: "email"))
        XCTAssertTrue(warnings.isEmpty)
    }

    func testSameValueReturnsFalseAndWarns() {
        XCTAssertFalse("same@example.com".isNotEmptyOrSame(as: "same@example.com", identifier: "email"))
        XCTAssertEqual(warnings.count, 1)
    }

    func testEmptyValueReturnsFalseAndWarns() {
        XCTAssertFalse("".isNotEmptyOrSame(as: "old@example.com", identifier: "email"))
        XCTAssertEqual(warnings.count, 1)
    }

    func testWhitespaceOnlyValueReturnsFalseAndWarns() {
        XCTAssertFalse("   ".isNotEmptyOrSame(as: "old@example.com", identifier: "email"))
        XCTAssertEqual(warnings.count, 1)
    }

    func testValueIsTrimmedBeforeComparison() {
        // Trimmed value equals the stored value -> treated as unchanged.
        XCTAssertFalse("  same  ".isNotEmptyOrSame(as: "same", identifier: "email"))
        XCTAssertEqual(warnings.count, 1)
    }
}
