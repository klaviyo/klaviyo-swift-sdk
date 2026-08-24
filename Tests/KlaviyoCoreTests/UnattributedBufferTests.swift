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

    /// Terse aggregate-event fixture.
    private func agg(_ value: String) -> UnattributedRequest {
        .aggregateEvent(Data(value.utf8))
    }

    /// Reads the persisted buffer from the store directory production writes to.
    private func loadBuffer() -> PersistedUnattributedBuffer? {
        loadPersisted(
            PersistedUnattributedBuffer.self, fileName: StoreFile.unattributed,
            directory: storeDirectory()
        )
    }

    func testAppendPersistsSynchronously() {
        let buffer = UnattributedBuffer()
        buffer.append(agg("a"))
        // Read straight off disk — append must write through before returning.
        XCTAssertEqual(loadBuffer()?.requests, [agg("a")])
    }

    func testHydratesFromDiskOnFirstAccess() {
        savePersisted(
            PersistedUnattributedBuffer(requests: [agg("x")]),
            fileName: StoreFile.unattributed, directory: storeDirectory()
        )
        let buffer = UnattributedBuffer()
        XCTAssertEqual(buffer.snapshot(), [agg("x")])
    }

    func testAbsentFileYieldsEmpty() {
        XCTAssertEqual(UnattributedBuffer().snapshot(), [])
    }

    func testCorruptFileYieldsEmptyAndRemovesFile() throws {
        // Write bytes that are not valid PersistedUnattributedBuffer JSON.
        let fileURL = storeDirectory().appendingPathComponent(StoreFile.unattributed)
        try environment.fileClient.write(Data("not json".utf8), fileURL)
        let buffer = UnattributedBuffer()
        XCTAssertEqual(buffer.snapshot(), [])
        XCTAssertFalse(environment.fileClient.fileExists(fileURL.path))
    }

    func testCapEvictsOldestWhenFull() {
        let buffer = UnattributedBuffer()
        for value in 0..<UnattributedBuffer.maxBufferSize {
            buffer.append(agg("\(value)"))
        }
        buffer.append(agg("newest"))
        let snap = buffer.snapshot()
        XCTAssertEqual(snap.count, UnattributedBuffer.maxBufferSize)
        XCTAssertEqual(snap.first, agg("1")) // "0" evicted
        XCTAssertEqual(snap.last, agg("newest"))
    }

    func testRemoveDrainedKeepsItemsAppendedDuringDrain() {
        let buffer = UnattributedBuffer()
        buffer.append(agg("1"))
        buffer.append(agg("2"))
        // Model a drain: it snapshots the current 2 items, then a 3rd is appended
        // (a concurrent enqueue that saw no apiKey) before the drained items are removed.
        let (_, cursor) = buffer.drainSnapshot()
        buffer.append(agg("3"))
        buffer.removeDrained(throughCursor: cursor)
        // Only the drained items are gone; the concurrently-appended item survives.
        XCTAssertEqual(buffer.snapshot(), [agg("3")])
    }

    func testDrainDoesNotDropAppendWhenCapEvictsDuringDrain() {
        let buffer = UnattributedBuffer()
        for value in 0..<UnattributedBuffer.maxBufferSize {
            buffer.append(agg("\(value)"))
        }
        let (_, cursor) = buffer.drainSnapshot() // maxBufferSize items
        // Concurrent enqueue during the drain: the buffer is at cap, so append evicts the
        // oldest (front) and stores the newest at the back.
        buffer.append(agg("newest"))
        buffer.removeDrained(throughCursor: cursor)
        // The item appended during the drain must survive, not be swept up by the trim.
        XCTAssertEqual(
            buffer.snapshot(), [agg("newest")],
            "item appended during a cap-evicting drain must survive"
        )
    }

    func testRemoveDrainedAllEmptiesMemoryAndRemovesFile() {
        let buffer = UnattributedBuffer()
        buffer.append(agg("a"))
        let (_, cursor) = buffer.drainSnapshot()
        buffer.removeDrained(throughCursor: cursor)
        XCTAssertEqual(buffer.snapshot(), [])
        XCTAssertNil(loadBuffer())
    }

    func testClearEmptiesMemoryAndRemovesFile() {
        let buffer = UnattributedBuffer()
        buffer.append(agg("a"))
        buffer.clear()
        XCTAssertEqual(buffer.snapshot(), [])
        XCTAssertNil(loadBuffer())
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
                agg("agg"),
                .profile(profilePayload),
                .pushToken(tokenPayload)
            ]
        )

        let data = try environment.encodeJSON(original)
        let decoded: PersistedUnattributedBuffer = try environment.decoder.decode(data)

        XCTAssertEqual(decoded, original)
    }
}
