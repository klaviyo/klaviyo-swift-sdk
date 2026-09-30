@testable import KlaviyoCore
import XCTest

final class PreInitMemoryBufferTests: XCTestCase {
    override func setUp() { super.setUp(); PreInitMemoryBuffer.shared.reset() }
    override func tearDown() { PreInitMemoryBuffer.shared.reset(); super.tearDown() }

    private func openedPush() -> UnattributedRequest {
        .event(CreateEventPayload(data: .init(name: "$opened_push")), .high)
    }

    func testAppendThenDrainReturnsAndClears() {
        PreInitMemoryBuffer.shared.append(openedPush())
        let first = PreInitMemoryBuffer.shared.drain()
        XCTAssertEqual(first.count, 1, "drain returns buffered requests")
        let second = PreInitMemoryBuffer.shared.drain()
        XCTAssertTrue(second.isEmpty, "drain clears the buffer (non-durable, one-shot)")
    }

    func testCapEvictsOldest() {
        for _ in 0..<(PreInitMemoryBuffer.maxBufferSize + 5) {
            PreInitMemoryBuffer.shared.append(openedPush())
        }
        XCTAssertEqual(PreInitMemoryBuffer.shared.drain().count,
                       PreInitMemoryBuffer.maxBufferSize,
                       "buffer is capped at maxBufferSize, dropping oldest")
    }
}
