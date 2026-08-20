//
//  UnattributedBufferTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/26.
//

@testable import KlaviyoCore
import XCTest

final class UnattributedBufferTests: XCTestCase {
    private var fileIO: FileIODouble!

    override func setUp() {
        super.setUp()
        fileIO = FileIODouble()
        environment = fileIO.makeEnvironment()
    }

    override func tearDown() {
        environment = KlaviyoEnvironment.test()
        fileIO = nil
        super.tearDown()
    }

    func testAppendPersistsSynchronously() {
        let buffer = UnattributedBuffer()
        buffer.append(.aggregateEvent(Data("a".utf8)))
        // Read straight off disk — append must write through before returning.
        let onDisk = loadPersisted(PersistedUnattributedBuffer.self, fileName: StoreFile.unattributed)
        XCTAssertEqual(onDisk?.requests, [.aggregateEvent(Data("a".utf8))])
    }

    func testHydratesFromDiskOnFirstAccess() {
        savePersisted(
            PersistedUnattributedBuffer(requests: [.aggregateEvent(Data("x".utf8))]),
            fileName: StoreFile.unattributed
        )
        let buffer = UnattributedBuffer()
        XCTAssertEqual(buffer.snapshot(), [.aggregateEvent(Data("x".utf8))])
    }

    func testAbsentFileYieldsEmpty() {
        XCTAssertEqual(UnattributedBuffer().snapshot(), [])
    }

    func testCorruptFileYieldsEmptyAndRemovesFile() throws {
        // Write bytes that are not valid PersistedUnattributedBuffer JSON.
        try environment.fileClient.write(
            Data("not json".utf8),
            environment.fileClient.libraryDirectory()
                .appendingPathComponent(StoreFile.unattributed)
        )
        let buffer = UnattributedBuffer()
        XCTAssertEqual(buffer.snapshot(), [])
        XCTAssertFalse(environment.fileClient.fileExists(
            environment.fileClient.libraryDirectory()
                .appendingPathComponent(StoreFile.unattributed).path))
    }

    func testCapEvictsOldestWhenFull() {
        let buffer = UnattributedBuffer()
        for i in 0..<UnattributedBuffer.maxBufferSize {
            buffer.append(.aggregateEvent(Data("\(i)".utf8)))
        }
        buffer.append(.aggregateEvent(Data("newest".utf8)))
        let snap = buffer.snapshot()
        XCTAssertEqual(snap.count, UnattributedBuffer.maxBufferSize)
        XCTAssertEqual(snap.first, .aggregateEvent(Data("1".utf8))) // "0" evicted
        XCTAssertEqual(snap.last, .aggregateEvent(Data("newest".utf8)))
    }

    func testRemoveDrainedRemovesPrefixAndKeepsItemsAppendedDuringDrain() {
        let buffer = UnattributedBuffer()
        buffer.append(.aggregateEvent(Data("1".utf8)))
        buffer.append(.aggregateEvent(Data("2".utf8)))
        // Model a drain: it snapshots the current 2 items, then a 3rd is appended
        // (a concurrent enqueue that saw no apiKey) before the drained prefix is removed.
        let drainedCount = buffer.snapshot().count
        buffer.append(.aggregateEvent(Data("3".utf8)))
        buffer.removeDrained(drainedCount)
        // Only the drained prefix is gone; the concurrently-appended item survives.
        XCTAssertEqual(buffer.snapshot(), [.aggregateEvent(Data("3".utf8))])
    }

    func testRemoveDrainedAllEmptiesMemoryAndRemovesFile() {
        let buffer = UnattributedBuffer()
        buffer.append(.aggregateEvent(Data("a".utf8)))
        buffer.removeDrained(1)
        XCTAssertEqual(buffer.snapshot(), [])
        XCTAssertNil(loadPersisted(PersistedUnattributedBuffer.self, fileName: StoreFile.unattributed))
    }

    func testClearEmptiesMemoryAndRemovesFile() {
        let buffer = UnattributedBuffer()
        buffer.append(.aggregateEvent(Data("a".utf8)))
        buffer.clear()
        XCTAssertEqual(buffer.snapshot(), [])
        XCTAssertNil(loadPersisted(PersistedUnattributedBuffer.self, fileName: StoreFile.unattributed))
    }

    func testPersistedBufferRoundTripsAllFourCases() throws {
        let eventPayload = CreateEventPayload(
            data: CreateEventPayload.Event(name: "Test", anonymousId: "anon-1"))
        let profilePayload = CreateProfilePayload(
            data: ProfilePayload(anonymousId: "anon-1"))
        let tokenPayload = PushTokenPayload(
            pushToken: "tok", enablement: "AUTHORIZED", background: "AVAILABLE",
            profile: ProfilePayload(anonymousId: "anon-1")
        )
        let original = PersistedUnattributedBuffer(
            version: PersistedUnattributedBuffer.currentVersion,
            requests: [
                .event(eventPayload, .high),
                .aggregateEvent(Data("agg".utf8)),
                .profile(profilePayload),
                .pushToken(tokenPayload)
            ]
        )

        let data = try environment.encodeJSON(original)
        let decoded: PersistedUnattributedBuffer = try environment.decoder.decode(data)

        XCTAssertEqual(decoded, original)
    }
}
