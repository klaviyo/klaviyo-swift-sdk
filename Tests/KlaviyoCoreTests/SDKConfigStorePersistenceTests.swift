//
//  SDKConfigStorePersistenceTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

@testable import KlaviyoCore
import Combine
import XCTest

final class SDKConfigStorePersistenceTests: XCTestCase {
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

    func testHydratesApiKeyFromDiskOnFirstRead() {
        savePersisted(PersistedConfig(version: 1, apiKey: "pk-persisted"), fileName: StoreFile.config)
        let store = SDKConfigStore()
        XCTAssertEqual(store.current.apiKey, "pk-persisted")
    }

    func testUpdateWritesThroughSynchronously() {
        let store = SDKConfigStore()
        store.update(KlaviyoConfig(apiKey: "pk-new"))
        // Read straight off disk — write-through must complete before update returns.
        let onDisk = loadPersisted(PersistedConfig.self, fileName: StoreFile.config)
        XCTAssertEqual(onDisk?.apiKey, "pk-new")
    }

    func testEmptyWhenNoFileAndDoesNotMint() {
        let store = SDKConfigStore()
        XCTAssertNil(store.current.apiKey)
        // config never self-persists on read
        XCTAssertNil(loadPersisted(PersistedConfig.self, fileName: StoreFile.config))
    }

    // MARK: - Thread safety

    func testConcurrentReadsAreRaceFree() {
        let store = SDKConfigStore()
        store.update(KlaviyoConfig(apiKey: "seed"))
        // Concurrent readers: `current` / `publisher` acquire the lock via `hydrateIfNeeded`, so this
        // catches races on `hydrated` under the thread sanitizer and must not crash. Writes persist
        // lock-free, so we deliberately don't hammer concurrent writes here (that would exercise
        // unsynchronized file I/O).
        DispatchQueue.concurrentPerform(iterations: 5000) { _ in
            _ = store.current
            _ = store.publisher
        }
        XCTAssertEqual(store.current.apiKey, "seed")
    }
}
