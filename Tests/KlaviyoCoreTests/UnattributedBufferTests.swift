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

    /// Terse push-token fixture — `value` only varies the token string, matching how a repeated
    /// pre-init fire (manual or automatic) looks in practice: same shape, latest token wins.
    private func token(_ value: String) -> UnattributedRequest {
        .pushToken(PushTokenPayload(
            pushToken: value, enablement: "AUTHORIZED", background: "AVAILABLE",
            profile: ProfilePayload(anonymousId: "anon-1")
        ))
    }

    /// Reads the persisted buffer from the store directory production writes to.
    private func loadBuffer() -> PersistedUnattributedBuffer? {
        loadPersisted(PersistedUnattributedBuffer.self, fileName: StoreFile.unattributed)
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
            fileName: StoreFile.unattributed
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

    // MARK: - Push-token coalescing

    func testAppendCoalescesRepeatedPushTokenToLatest() {
        let buffer = UnattributedBuffer()
        buffer.append(token("a"))
        buffer.append(token("b"))
        buffer.append(token("c"))
        XCTAssertEqual(buffer.snapshot(), [token("c")])
    }

    func testPushTokenCoalescingDoesNotAffectOtherBufferedRequests() {
        let buffer = UnattributedBuffer()
        buffer.append(agg("1"))
        buffer.append(token("a"))
        buffer.append(agg("2"))
        buffer.append(token("b"))
        // The stale token is dropped; other request types are untouched. The coalesced token
        // is re-appended at the back rather than preserving its original position — acceptable
        // since push-token requests are idempotent w.r.t. ordering against unrelated requests.
        XCTAssertEqual(buffer.snapshot(), [agg("1"), agg("2"), token("b")])
    }

    func testPushTokenCoalescingDoesNotEvictOtherEntriesAtCap() {
        let buffer = UnattributedBuffer()
        for value in 0..<(UnattributedBuffer.maxBufferSize - 1) {
            buffer.append(agg("\(value)"))
        }
        buffer.append(token("a")) // buffer now exactly at cap
        buffer.append(token("b")) // coalesces token("a") away first, so nothing is evicted
        let snap = buffer.snapshot()
        XCTAssertEqual(snap.count, UnattributedBuffer.maxBufferSize)
        XCTAssertEqual(snap.first, agg("0"), "coalescing a push token must not evict an unrelated entry")
        XCTAssertEqual(snap.last, token("b"))
    }

    func testHydrationCoalescesPersistedDuplicatePushTokens() {
        // A file with more than one buffered token can only exist from before this coalescing
        // existed (or from disk corruption) — hydration must clean it up, not just live appends.
        savePersisted(
            PersistedUnattributedBuffer(requests: [agg("1"), token("a"), token("b"), token("c")]),
            fileName: StoreFile.unattributed
        )
        let buffer = UnattributedBuffer()
        XCTAssertEqual(buffer.snapshot(), [agg("1"), token("c")])
        // The normalized buffer must also be the one written back to disk.
        XCTAssertEqual(loadBuffer()?.requests, [agg("1"), token("c")])
    }

    func testRemoveDrainedSurvivesConcurrentPushTokenCoalesce() {
        let buffer = UnattributedBuffer()
        buffer.append(token("1"))
        // Model a drain: it snapshots the current buffer, then a concurrent automatic fire
        // coalesces the just-drained token before the drain removes what it saw.
        let (_, cursor) = buffer.drainSnapshot()
        buffer.append(token("2"))
        buffer.removeDrained(throughCursor: cursor)
        // The coalesced replacement must survive — it was never part of the drained snapshot.
        XCTAssertEqual(buffer.snapshot(), [token("2")])
    }

    func testPersistedBufferRoundTripsAllCases() throws {
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
                .pushToken(tokenPayload),
                .trackingLinkClick(
                    trackingLink: URL(string: "https://klaviyo.com/tracking/abc")!,
                    clickTime: Date(timeIntervalSince1970: 1_234_567_890),
                    profileInfo: ProfilePayload(anonymousId: "anon-1")
                )
            ]
        )

        let data = try environment.encodeJSON(original)
        let decoded: PersistedUnattributedBuffer = try environment.decoder.decode(data)

        XCTAssertEqual(decoded, original)
    }
}
