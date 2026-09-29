//
//  QueueStoreByteBudgetTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import XCTest

final class QueueStoreByteBudgetTests: XCTestCase {
    private func request(_ id: String, at timestamp: TimeInterval) -> KlaviyoRequest {
        KlaviyoRequest(
            id: id,
            endpoint: .createProfile("foo", CreateProfilePayload(data: .test)),
            enqueuedAt: Date(timeIntervalSince1970: timestamp)
        )
    }

    private func makeStore(serializedSize: @escaping (KlaviyoRequest) throws -> Int) -> QueueStore {
        QueueStore(
            diskIO: SpyDiskIO().makeIO(),
            scheduler: ManualPersistScheduler().makeScheduler(),
            emitWarning: { _ in },
            serializedSize: serializedSize
        )
    }

    func testByteBudgetEvictsOldestBeforeCountCapacity() {
        let requestSize = QueueStore.maxQueueBytes / 3 + 1
        let store = makeStore { _ in requestSize }

        store.enqueue(request("first", at: 1))
        store.enqueue(request("second", at: 2))
        store.enqueue(request("third", at: 3))

        XCTAssertEqual(store.requests.map(\.id), ["second", "third"])
        XCTAssertEqual(store.byteCount, requestSize * 2)
        XCTAssertLessThanOrEqual(store.byteCount, QueueStore.maxQueueBytes)
    }

    func testLoneOversizedRequestEvictsEverythingElseAndIsAdmitted() {
        let store = makeStore { request in
            request.id == "oversized" ? QueueStore.maxQueueBytes + 1 : 100
        }

        store.enqueue(request("existing", at: 1))
        store.enqueue(request("oversized", at: 2))

        XCTAssertEqual(store.requests.map(\.id), ["oversized"])
        XCTAssertGreaterThan(store.byteCount, QueueStore.maxQueueBytes)
    }
}
