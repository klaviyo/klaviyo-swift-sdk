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

    func testTheMarkerIsWrittenUnderApplicationSupport() {
        assertWriteRoutesToApplicationSupport(fileName: StoreFile.profileResetPending) {
            ProfileResetSignal.publish()
        }
    }
}
