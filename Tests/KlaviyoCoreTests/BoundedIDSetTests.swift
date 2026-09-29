//
//  BoundedIDSetTests.swift
//  KlaviyoCoreTests
//
//  Created by Glenn Brannelly on 6/1/26.
//

@testable import KlaviyoCore
import XCTest

class BoundedIDSetTests: XCTestCase {
    // MARK: - insert / contains

    func testInsertedIDIsFound() {
        // Given
        let idSet = BoundedIDSet<String>()

        // When
        idSet.insert("abc")

        // Then
        XCTAssertTrue(idSet.contains("abc"))
    }

    func testUninsertedIDIsNotFound() {
        // Given
        let idSet = BoundedIDSet<String>()

        // When / Then
        XCTAssertFalse(idSet.contains("unknown"))
    }

    func testDuplicateInsertDoesNotAdvanceEvictionOrder() {
        // Given
        let idSet = BoundedIDSet<String>(capacity: 4)
        idSet.insert("first")
        idSet.insert("first") // duplicate — must not advance eviction position

        // When — fill remaining capacity slots, then overflow by one to trigger eviction
        idSet.insert("b")
        idSet.insert("c")
        idSet.insert("d")
        idSet.insert("e") // causes eviction

        // Then — "first" is evicted as oldest; the duplicate did not re-enqueue it
        XCTAssertFalse(idSet.contains("first"), "duplicate insert must not reset eviction position")
    }

    // MARK: - FIFO eviction

    func testFIFOEvictionRemovesOldestAtCapacity() {
        // Given
        let capacity = 4
        let idSet = BoundedIDSet<String>(capacity: capacity)
        for index in 0..<capacity {
            idSet.insert("id-\(index)")
        }

        // When
        idSet.insert("id-overflow")

        // Then
        XCTAssertFalse(idSet.contains("id-0"), "oldest entry should be evicted first")
        XCTAssertTrue(idSet.contains("id-overflow"))
        XCTAssertTrue(idSet.contains("id-\(capacity - 1)"))
    }

    func testSubsequentInsertAfterEvictionIsTracked() {
        // Given
        let idSet = BoundedIDSet<String>(capacity: 2)
        idSet.insert("a")
        idSet.insert("b")
        idSet.insert("c") // evicts "a"

        // When
        idSet.insert("a") // re-insert formerly evicted ID

        // Then
        XCTAssertTrue(idSet.contains("a"))
        XCTAssertFalse(idSet.contains("b"), "b was evicted to make room for re-inserted 'a'")
    }

    // MARK: - clear

    func testClearRemovesAllEntries() {
        // Given
        let idSet = BoundedIDSet<String>()
        idSet.insert("abc")
        idSet.insert("def")

        // When
        idSet.clear()

        // Then
        XCTAssertFalse(idSet.contains("abc"))
        XCTAssertFalse(idSet.contains("def"))
    }

    func testInsertAfterClearWorks() {
        // Given
        let idSet = BoundedIDSet<String>()
        idSet.insert("abc")
        idSet.clear()

        // When
        idSet.insert("abc")

        // Then
        XCTAssertTrue(idSet.contains("abc"))
    }

    // MARK: - Generic type

    func testWorksWithIntegerIDs() {
        // Given
        let idSet = BoundedIDSet<Int>(capacity: 3)

        // When
        idSet.insert(1)
        idSet.insert(2)

        // Then
        XCTAssertTrue(idSet.contains(1))
        XCTAssertTrue(idSet.contains(2))
        XCTAssertFalse(idSet.contains(3))
    }

    // MARK: - Thread safety

    func testConcurrentAccessDoesNotCrash() async {
        // Given
        let idSet = BoundedIDSet<String>()

        // When
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask { idSet.insert("write-\(index)") }
            }
            for index in 0..<4 {
                group.addTask { _ = idSet.contains("read-\(index)") }
            }
        }

        // Then — no crash; state is consistent (all writers committed)
        for index in 0..<8 {
            XCTAssertTrue(idSet.contains("write-\(index)"))
        }
    }
}
