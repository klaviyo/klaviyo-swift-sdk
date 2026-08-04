// Tests/KlaviyoCoreTests/SDKConfigStorePersistenceTests.swift
import Combine
import XCTest
@testable import KlaviyoCore

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
}
