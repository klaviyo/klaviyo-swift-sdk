//
//  ProfileResetSignalTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import XCTest

final class ProfileResetSignalTests: XCTestCase {
    private var fileIO: FileIODouble!

    override func setUp() {
        super.setUp()
        fileIO = FileIODouble()
        environment = fileIO.makeEnvironment()
        ProfileResetSignal.reset()
    }

    override func tearDown() {
        ProfileResetSignal.reset()
        environment = KlaviyoEnvironment.test()
        fileIO = nil
        super.tearDown()
    }

    private func nextElement(of stream: AsyncStream<Void>, timeout: TimeInterval = 2) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    func testNothingIsPendingBeforeAnyReset() {
        XCTAssertNil(ProfileResetSignal.pendingMarker())
    }

    func testAResetWithNoListenerLeavesAMarkerForALaterOne() {
        ProfileResetSignal.publish()
        XCTAssertNotNil(ProfileResetSignal.pendingMarker())
    }

    func testTheMarkerSurvivesUntilItIsAcknowledged() throws {
        ProfileResetSignal.publish()
        let marker = try XCTUnwrap(ProfileResetSignal.pendingMarker())
        XCTAssertEqual(ProfileResetSignal.pendingMarker(), marker, "reading the marker must not consume it")
        ProfileResetSignal.acknowledge(marker)
        XCTAssertNil(ProfileResetSignal.pendingMarker())
    }

    func testAcknowledgingAnOlderMarkerKeepsANewerReset() throws {
        var ids = [UUID(), UUID()]
        environment.uuid = { ids.removeFirst() }
        ProfileResetSignal.publish()
        let first = try XCTUnwrap(ProfileResetSignal.pendingMarker())
        ProfileResetSignal.publish()
        ProfileResetSignal.acknowledge(first)
        XCTAssertNotNil(ProfileResetSignal.pendingMarker(), "a reset that arrived during the clear must not be lost")
    }

    func testAListenerHearsALiveReset() async {
        let stream = ProfileResetSignal.resets()
        ProfileResetSignal.publish()
        let heard = await nextElement(of: stream)
        XCTAssertTrue(heard)
    }

    func testEveryActiveListenerHearsAReset() async {
        let first = ProfileResetSignal.resets()
        let second = ProfileResetSignal.resets()
        ProfileResetSignal.publish()
        let heardFirst = await nextElement(of: first)
        let heardSecond = await nextElement(of: second)
        XCTAssertTrue(heardFirst)
        XCTAssertTrue(heardSecond)
    }

    func testALateListenerDoesNotHearAResetThatAlreadyHappened() async {
        ProfileResetSignal.publish()
        let late = ProfileResetSignal.resets()
        let heard = await nextElement(of: late, timeout: 0.3)
        XCTAssertFalse(heard, "the live signal must not replay; the marker is how a late listener catches up")
    }

    func testResetsDuringOneHandlerCollapseIntoOne() async {
        let stream = ProfileResetSignal.resets()
        ProfileResetSignal.publish()
        ProfileResetSignal.publish()
        ProfileResetSignal.publish()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        let second = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await iterator.next() != nil }
            group.addTask {
                try? await Task.sleep(nanoseconds: 300_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        XCTAssertFalse(second)
    }

    func testAMarkerThatCannotBeDecodedIsTreatedAsNone() {
        let url = storeDirectory().appendingPathComponent(StoreFile.profileResetPending)
        try? environment.fileClient.write(Data("not json".utf8), url)
        XCTAssertNil(ProfileResetSignal.pendingMarker())
    }

    /// Makes every write fail, as a full disk would, while reads and removals still work.
    private func failAllWrites() {
        let working = environment.fileClient
        environment.fileClient = FileClient(
            write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) },
            fileExists: working.fileExists,
            removeItem: working.removeItem,
            libraryDirectory: working.libraryDirectory,
            applicationSupportDirectory: working.applicationSupportDirectory
        )
    }

    func testAResetIsStillPendingWhenTheMarkerCannotBeWritten() throws {
        failAllWrites()
        ProfileResetSignal.publish()
        XCTAssertNotNil(ProfileResetSignal.pendingMarker(), "a running listener must still find the reset")
    }

    func testAnAcknowledgedResetIsGoneEvenWhenItWasNeverWritten() throws {
        failAllWrites()
        ProfileResetSignal.publish()
        let marker = try XCTUnwrap(ProfileResetSignal.pendingMarker())
        ProfileResetSignal.acknowledge(marker)
        XCTAssertNil(ProfileResetSignal.pendingMarker())
    }

    func testAnOldAcknowledgementKeepsANewerResetThatWasNeverWritten() throws {
        var ids = [UUID(), UUID()]
        environment.uuid = { ids.removeFirst() }
        ProfileResetSignal.publish()
        let first = try XCTUnwrap(ProfileResetSignal.pendingMarker())
        failAllWrites()
        ProfileResetSignal.publish()
        ProfileResetSignal.acknowledge(first)
        XCTAssertNotNil(ProfileResetSignal.pendingMarker(), "the newer reset must survive the older acknowledgement")
    }

    func testAcknowledgingAResetAlsoRemovesAnOlderMarkerLeftOnDisk() throws {
        // Launch 1 leaves a marker on disk; launch 2's reset cannot overwrite it.
        ProfileResetSignal.publish()
        ProfileResetSignal.forgetInMemoryStateForTesting()
        failAllWrites()
        ProfileResetSignal.publish()
        let marker = try XCTUnwrap(ProfileResetSignal.pendingMarker())
        ProfileResetSignal.acknowledge(marker)
        // A later launch reads from disk only.
        ProfileResetSignal.forgetInMemoryStateForTesting()
        XCTAssertNil(ProfileResetSignal.pendingMarker(), "the clear covered the older marker too")
    }

    func testAMarkerFromAnEarlierLaunchIsFoundAndAcknowledged() throws {
        ProfileResetSignal.publish()
        ProfileResetSignal.forgetInMemoryStateForTesting()
        let marker = try XCTUnwrap(ProfileResetSignal.pendingMarker(), "a new launch reads the disk copy")
        ProfileResetSignal.acknowledge(marker)
        XCTAssertNil(ProfileResetSignal.pendingMarker())
    }

    func testTheMarkerIsWrittenUnderApplicationSupport() {
        assertWriteRoutesToApplicationSupport(fileName: StoreFile.profileResetPending) {
            ProfileResetSignal.publish()
        }
    }
}
