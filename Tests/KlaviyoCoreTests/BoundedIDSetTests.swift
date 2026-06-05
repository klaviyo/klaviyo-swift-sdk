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
        let set = BoundedIDSet<String>()

        // When
        set.insert("abc")

        // Then
        XCTAssertTrue(set.contains("abc"))
    }

    func testUninsertedIDIsNotFound() {
        // Given
        let set = BoundedIDSet<String>()

        // When / Then
        XCTAssertFalse(set.contains("unknown"))
    }

    func testDuplicateInsertDoesNotAdvanceEvictionOrder() {
        // Given
        let set = BoundedIDSet<String>(capacity: 4)
        set.insert("first")
        set.insert("first") // duplicate — must not advance eviction position

        // When — fill remaining capacity slots, then overflow by one to trigger eviction
        set.insert("b")
        set.insert("c")
        set.insert("d")
        set.insert("e") // causes eviction

        // Then — "first" is evicted as oldest; the duplicate did not re-enqueue it
        XCTAssertFalse(set.contains("first"), "duplicate insert must not reset eviction position")
    }

    // MARK: - FIFO eviction

    func testFIFOEvictionRemovesOldestAtCapacity() {
        // Given
        let capacity = 4
        let set = BoundedIDSet<String>(capacity: capacity)
        for i in 0..<capacity {
            set.insert("id-\(i)")
        }

        // When
        set.insert("id-overflow")

        // Then
        XCTAssertFalse(set.contains("id-0"), "oldest entry should be evicted first")
        XCTAssertTrue(set.contains("id-overflow"))
        XCTAssertTrue(set.contains("id-\(capacity - 1)"))
    }

    func testSubsequentInsertAfterEvictionIsTracked() {
        // Given
        let set = BoundedIDSet<String>(capacity: 2)
        set.insert("a")
        set.insert("b")
        set.insert("c") // evicts "a"

        // When
        set.insert("a") // re-insert formerly evicted ID

        // Then
        XCTAssertTrue(set.contains("a"))
        XCTAssertFalse(set.contains("b"), "b should now be the oldest and get evicted next")
    }

    // MARK: - clear

    func testClearRemovesAllEntries() {
        // Given
        let set = BoundedIDSet<String>()
        set.insert("abc")
        set.insert("def")

        // When
        set.clear()

        // Then
        XCTAssertFalse(set.contains("abc"))
        XCTAssertFalse(set.contains("def"))
    }

    func testInsertAfterClearWorks() {
        // Given
        let set = BoundedIDSet<String>()
        set.insert("abc")
        set.clear()

        // When
        set.insert("abc")

        // Then
        XCTAssertTrue(set.contains("abc"))
    }

    // MARK: - Generic type

    func testWorksWithIntegerIDs() {
        // Given
        let set = BoundedIDSet<Int>(capacity: 3)

        // When
        set.insert(1)
        set.insert(2)

        // Then
        XCTAssertTrue(set.contains(1))
        XCTAssertTrue(set.contains(2))
        XCTAssertFalse(set.contains(3))
    }

    // MARK: - Thread safety

    func testConcurrentAccessDoesNotCrash() async {
        // Given
        let set = BoundedIDSet<String>()

        // When
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<8 {
                group.addTask { set.insert("write-\(i)") }
            }
            for i in 0..<4 {
                group.addTask { _ = set.contains("read-\(i)") }
            }
        }

        // Then — no crash; state is consistent (all writers committed)
        for i in 0..<8 {
            XCTAssertTrue(set.contains("write-\(i)"))
        }
    }
}
