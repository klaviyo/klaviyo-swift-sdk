//
//  QueuePersistenceTests.swift
//  KlaviyoCoreTests
//
//  Created by Claude Code on 2025-11-10.
//

@testable import KlaviyoCore
import XCTest

final class QueuePersistenceTests: XCTestCase {
    var persistence: QueuePersistence!
    var testFileClient: TestFileClient!
    var testAPIKey: String!

    override func setUp() throws {
        testAPIKey = "test-api-key-123"
        testFileClient = TestFileClient()
        persistence = QueuePersistence(
            fileClient: testFileClient,
            apiKey: testAPIKey
        )
    }

    override func tearDown() throws {
        try? persistence.clear()
        testFileClient = nil
        persistence = nil
    }

    // MARK: - Save Tests

    func testSaveCreatesFile() throws {
        let immediate = [makeQueuedRequest(id: "immediate1")]
        let normal = [makeQueuedRequest(id: "normal1")]

        try persistence.save(immediate: immediate, normal: normal)

        XCTAssertTrue(testFileClient.writtenFiles.count == 1)
        XCTAssertTrue(testFileClient.fileExists("klaviyo-\(testAPIKey!)-queue-v2.json"))
    }

    func testSaveWritesCorrectData() throws {
        let immediate = [
            makeQueuedRequest(id: "immediate1", retryCount: 1),
            makeQueuedRequest(id: "immediate2", retryCount: 0)
        ]
        let normal = [
            makeQueuedRequest(id: "normal1", retryCount: 2)
        ]

        try persistence.save(immediate: immediate, normal: normal)

        // Decode saved data
        let savedData = testFileClient.writtenFiles.first!.value
        let decoder = JSONDecoder()
        let state = try decoder.decode(PersistedQueueState.self, from: savedData)

        XCTAssertEqual(state.version, "2.0")
        XCTAssertEqual(state.apiKey, testAPIKey)
        XCTAssertEqual(state.immediate.count, 2)
        XCTAssertEqual(state.normal.count, 1)
        XCTAssertEqual(state.immediate[0].retryCount, 1)
        XCTAssertEqual(state.normal[0].retryCount, 2)
    }

    func testSaveEmptyQueues() throws {
        try persistence.save(immediate: [], normal: [])

        let savedData = testFileClient.writtenFiles.first!.value
        let decoder = JSONDecoder()
        let state = try decoder.decode(PersistedQueueState.self, from: savedData)

        XCTAssertEqual(state.immediate.count, 0)
        XCTAssertEqual(state.normal.count, 0)
    }

    // MARK: - Load Tests

    func testLoadNonExistentFileReturnsEmpty() {
        let (immediate, normal) = persistence.load()

        XCTAssertEqual(immediate.count, 0)
        XCTAssertEqual(normal.count, 0)
    }

    func testLoadValidFile() throws {
        // First save some data
        let savedImmediate = [makeQueuedRequest(id: "immediate1", retryCount: 1)]
        let savedNormal = [makeQueuedRequest(id: "normal1", retryCount: 2)]
        try persistence.save(immediate: savedImmediate, normal: savedNormal)

        // Now load it
        let (loadedImmediate, loadedNormal) = persistence.load()

        XCTAssertEqual(loadedImmediate.count, 1)
        XCTAssertEqual(loadedNormal.count, 1)
        XCTAssertEqual(loadedImmediate[0].id, "immediate1")
        XCTAssertEqual(loadedImmediate[0].retryCount, 1)
        XCTAssertEqual(loadedNormal[0].id, "normal1")
        XCTAssertEqual(loadedNormal[0].retryCount, 2)
    }

    func testLoadCorruptFileReturnsEmpty() {
        // Write corrupt JSON
        let corruptData = "not valid json".data(using: .utf8)!
        testFileClient.files["klaviyo-\(testAPIKey!)-queue-v2.json"] = corruptData

        let (immediate, normal) = persistence.load()

        XCTAssertEqual(immediate.count, 0)
        XCTAssertEqual(normal.count, 0)
        // File should be removed
        XCTAssertFalse(testFileClient.fileExists("klaviyo-\(testAPIKey!)-queue-v2.json"))
    }

    func testLoadAPIKeyMismatchReturnsEmpty() throws {
        // Save with one API key
        try persistence.save(immediate: [makeQueuedRequest()], normal: [])

        // Create new persistence with different API key
        let differentPersistence = QueuePersistence(
            fileClient: testFileClient,
            apiKey: "different-api-key"
        )

        let (immediate, normal) = differentPersistence.load()

        XCTAssertEqual(immediate.count, 0)
        XCTAssertEqual(normal.count, 0)
    }

    func testLoadVersionMismatchLogsWarning() throws {
        // Manually create state with different version
        let state = PersistedQueueState(
            version: "1.0",
            apiKey: testAPIKey,
            immediate: [makeQueuedRequest()],
            normal: []
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        testFileClient.files["klaviyo-\(testAPIKey!)-queue-v2.json"] = data

        // Should still load despite version mismatch
        let (immediate, normal) = persistence.load()

        XCTAssertEqual(immediate.count, 1)
        XCTAssertEqual(normal.count, 0)
    }

    // MARK: - Clear Tests

    func testClearRemovesFile() throws {
        try persistence.save(immediate: [makeQueuedRequest()], normal: [])
        XCTAssertTrue(persistence.exists())

        try persistence.clear()

        XCTAssertFalse(persistence.exists())
    }

    func testClearNonExistentFileDoesNotThrow() throws {
        XCTAssertNoThrow(try persistence.clear())
    }

    // MARK: - Exists Tests

    func testExistsReturnsFalseForNewPersistence() {
        XCTAssertFalse(persistence.exists())
    }

    func testExistsReturnsTrueAfterSave() throws {
        try persistence.save(immediate: [], normal: [])
        XCTAssertTrue(persistence.exists())
    }

    // MARK: - Backoff Persistence Tests

    func testSaveAndLoadWithBackoff() throws {
        let backoffDate = Date().addingTimeInterval(60)
        let queuedRequest = QueuedRequest(
            request: makeTestRequest(id: "test"),
            retryCount: 3,
            createdAt: Date(),
            backoffUntil: backoffDate
        )

        try persistence.save(immediate: [queuedRequest], normal: [])

        let (loaded, _) = persistence.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].retryCount, 3)
        XCTAssertNotNil(loaded[0].backoffUntil)
        XCTAssertEqual(loaded[0].backoffUntil?.timeIntervalSince1970,
                       backoffDate.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    // MARK: - Helper Methods

    private func makeTestRequest(id: String? = nil) -> KlaviyoRequest {
        let endpoint = KlaviyoEndpoint.createProfile(
            profilePayload: .init(
                data: .init(
                    type: .profile,
                    attributes: .init(
                        email: "test@example.com",
                        phoneNumber: nil,
                        externalId: nil,
                        anonymousId: "test-id",
                        properties: [:]
                    )
                )
            )
        )
        return KlaviyoRequest(id: id ?? UUID().uuidString, endpoint: endpoint)
    }

    private func makeQueuedRequest(id: String? = nil, retryCount: Int = 0) -> QueuedRequest {
        QueuedRequest(
            request: makeTestRequest(id: id),
            retryCount: retryCount,
            createdAt: Date(),
            backoffUntil: nil
        )
    }
}

// MARK: - Test File Client

class TestFileClient: FileClient {
    var files: [String: Data] = [:]
    var writtenFiles: [(key: String, value: Data)] = []

    init() {
        super.init(
            write: { [weak self] data, url in
                let path = url.lastPathComponent
                self?.files[path] = data
                self?.writtenFiles.append((key: path, value: data))
            },
            fileExists: { [weak self] path in
                let filename = URL(fileURLWithPath: path).lastPathComponent
                return self?.files[filename] != nil
            },
            removeItem: { [weak self] path in
                let filename = URL(fileURLWithPath: path).lastPathComponent
                self?.files.removeValue(forKey: filename)
            },
            libraryDirectory: {
                URL(fileURLWithPath: "/tmp/test-library")
            }
        )
    }
}

// Extend environment to support test data reading
extension KlaviyoEnvironment {
    static var testDataFromUrl: (URL) throws -> Data = { url in
        let filename = url.lastPathComponent
        // Access test file client through global state (not ideal but works for testing)
        guard let data = testFileClientInstance?.files[filename] else {
            throw NSError(domain: "test", code: 404, userInfo: nil)
        }
        return data
    }
}

var testFileClientInstance: TestFileClient?
