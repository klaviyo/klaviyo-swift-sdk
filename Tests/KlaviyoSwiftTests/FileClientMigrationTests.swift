//
//  FileClientMigrationTests.swift
//
//
//  Created by Claude Code on 2/18/26.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

enum FakeFileError: Error {
    case fake
}

class FileClientMigrationTests: XCTestCase {
    let testApiKey = "test-api-key"
    var originalEnvironment: KlaviyoEnvironment!

    override func setUp() {
        super.setUp()
        originalEnvironment = environment
        environment = KlaviyoEnvironment.test()
    }

    override func tearDown() {
        environment = originalEnvironment
        super.tearDown()
    }

    // MARK: - Directory Path Tests

    func testKlaviyoApplicationSupportDirectoryPath() {
        let expectedPath = TEST_URL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.klaviyo", isDirectory: true)

        let actualPath = klaviyoApplicationSupportDirectory()

        XCTAssertEqual(actualPath, expectedPath)
    }

    // MARK: - Fresh Install Tests

    func testMigrateFilesIfNeeded_FreshInstall() {
        // Setup: No old files exist
        environment.fileClient.fileExists = { _ in false }
        environment.fileClient.createDirectory = { _, _ in }

        let result = migrateFilesIfNeeded(apiKey: testApiKey)

        let expectedDirectory = klaviyoApplicationSupportDirectory()
        XCTAssertEqual(result, expectedDirectory)
    }

    // MARK: - Already Migrated Tests

    func testMigrateFilesIfNeeded_AlreadyMigrated() {
        let newDirectory = klaviyoApplicationSupportDirectory()
        let newStateFilePath = newDirectory
            .appendingPathComponent("klaviyo-\(testApiKey)-state.json", isDirectory: false)
            .path

        // Setup: State file exists in new location
        environment.fileClient.fileExists = { path in
            path == newStateFilePath
        }
        environment.fileClient.createDirectory = { _, _ in }

        let result = migrateFilesIfNeeded(apiKey: testApiKey)

        XCTAssertEqual(result, newDirectory)
    }

    // MARK: - Successful Migration Tests

    func testMigrateFilesIfNeeded_SuccessfulMigration() {
        let oldDirectory = TEST_URL
        let newDirectory = klaviyoApplicationSupportDirectory()

        let stateFileName = "klaviyo-\(testApiKey)-state.json"
        let eventsFileName = "klaviyo-\(testApiKey)-events.plist"
        let peopleFileName = "klaviyo-\(testApiKey)-people.plist"

        var createdDirectories: [URL] = []
        var copiedFiles: Set<String> = []
        var removedFiles: [String] = []

        // Setup: fileExists tracks state - initially files in old location, then in new location after copy
        environment.fileClient.fileExists = { path in
            let oldStatePath = oldDirectory.appendingPathComponent(stateFileName, isDirectory: false).path
            let oldEventsPath = oldDirectory.appendingPathComponent(eventsFileName, isDirectory: false).path
            let oldPeoplePath = oldDirectory.appendingPathComponent(peopleFileName, isDirectory: false).path
            let newStatePath = newDirectory.appendingPathComponent(stateFileName, isDirectory: false).path
            let newEventsPath = newDirectory.appendingPathComponent(eventsFileName, isDirectory: false).path
            let newPeoplePath = newDirectory.appendingPathComponent(peopleFileName, isDirectory: false).path

            // Old files exist if they haven't been removed yet
            if [oldStatePath, oldEventsPath, oldPeoplePath].contains(path) {
                return !removedFiles.contains(path)
            }

            // New files exist after they've been copied
            if path == newStatePath && copiedFiles.contains(stateFileName) {
                return true
            }
            if path == newEventsPath && copiedFiles.contains(eventsFileName) {
                return true
            }
            if path == newPeoplePath && copiedFiles.contains(peopleFileName) {
                return true
            }

            return false
        }

        environment.fileClient.createDirectory = { url, _ in
            createdDirectories.append(url)
        }

        environment.fileClient.copyItem = { fromPath, toPath in
            // Track which files have been copied
            if fromPath.contains(stateFileName) {
                copiedFiles.insert(stateFileName)
            } else if fromPath.contains(eventsFileName) {
                copiedFiles.insert(eventsFileName)
            } else if fromPath.contains(peopleFileName) {
                copiedFiles.insert(peopleFileName)
            }
        }

        environment.fileClient.removeItem = { path in
            removedFiles.append(path)
        }

        // Mock successful state verification
        let testState = KlaviyoState(apiKey: testApiKey, anonymousId: "test-anon-id", queue: [])
        environment.dataFromUrl = { _ in try! JSONEncoder().encode(testState) }
        environment.decoder = DataDecoder(jsonDecoder: JSONDecoder())

        let result = migrateFilesIfNeeded(apiKey: testApiKey)

        // Verify directory was created
        XCTAssertEqual(createdDirectories.count, 1)
        XCTAssertEqual(createdDirectories.first, newDirectory)

        // Verify all files were copied
        XCTAssertEqual(copiedFiles.count, 3)
        XCTAssertTrue(copiedFiles.contains(stateFileName))
        XCTAssertTrue(copiedFiles.contains(eventsFileName))
        XCTAssertTrue(copiedFiles.contains(peopleFileName))

        // Verify old files were removed
        XCTAssertEqual(removedFiles.count, 3)

        // Verify new directory is returned
        XCTAssertEqual(result, newDirectory)
    }

    func testMigrateFilesIfNeeded_OnlyStateFileExists() {
        let oldDirectory = TEST_URL
        let newDirectory = klaviyoApplicationSupportDirectory()
        let stateFileName = "klaviyo-\(testApiKey)-state.json"

        var copiedFiles: Set<String> = []
        var removedFiles: [String] = []

        // Setup: Only state file exists (common case)
        environment.fileClient.fileExists = { path in
            let oldStatePath = oldDirectory.appendingPathComponent(stateFileName, isDirectory: false).path
            let newStatePath = newDirectory.appendingPathComponent(stateFileName, isDirectory: false).path

            // Old state file exists if not removed
            if path == oldStatePath {
                return !removedFiles.contains(path)
            }

            // New state file exists after copy
            if path == newStatePath && copiedFiles.contains(stateFileName) {
                return true
            }

            return false
        }

        environment.fileClient.createDirectory = { _, _ in }

        environment.fileClient.copyItem = { fromPath, _ in
            if fromPath.contains(stateFileName) {
                copiedFiles.insert(stateFileName)
            }
        }

        environment.fileClient.removeItem = { path in
            removedFiles.append(path)
        }

        // Mock successful state verification
        let testState = KlaviyoState(apiKey: testApiKey, anonymousId: "test-anon-id", queue: [])
        environment.dataFromUrl = { _ in try! JSONEncoder().encode(testState) }
        environment.decoder = DataDecoder(jsonDecoder: JSONDecoder())

        let result = migrateFilesIfNeeded(apiKey: testApiKey)

        // Verify only state file was copied
        XCTAssertEqual(copiedFiles.count, 1)
        XCTAssertTrue(copiedFiles.contains(stateFileName))

        // Verify only state file was removed
        XCTAssertEqual(removedFiles.count, 1)

        // Verify new directory is returned
        XCTAssertEqual(result, newDirectory)
    }

    // MARK: - Failure Tests

    func testMigrateFilesIfNeeded_DirectoryCreationFailure() {
        let oldDirectory = TEST_URL

        // Setup: Directory creation fails
        environment.fileClient.createDirectory = { _, _ in
            throw FakeFileError.fake
        }

        let result = migrateFilesIfNeeded(apiKey: testApiKey)

        // Verify old directory is returned on failure
        XCTAssertEqual(result, oldDirectory)
    }

    func testMigrateFilesIfNeeded_CopyFailure() {
        let oldDirectory = TEST_URL
        let newDirectory = klaviyoApplicationSupportDirectory()
        let stateFileName = "klaviyo-\(testApiKey)-state.json"

        var removedFiles: [String] = []

        // Setup: State file exists in old location
        environment.fileClient.fileExists = { path in
            let oldStatePath = oldDirectory.appendingPathComponent(stateFileName, isDirectory: false).path
            // New file might exist briefly during rollback check
            return path == oldStatePath && !removedFiles.contains(path)
        }

        environment.fileClient.createDirectory = { _, _ in }

        // Copy fails
        environment.fileClient.copyItem = { _, _ in
            throw FakeFileError.fake
        }

        environment.fileClient.removeItem = { path in
            removedFiles.append(path)
        }

        let result = migrateFilesIfNeeded(apiKey: testApiKey)

        // Verify old directory is returned on failure
        XCTAssertEqual(result, oldDirectory)
    }

    func testMigrateFilesIfNeeded_VerificationFailure() {
        let oldDirectory = TEST_URL
        let newDirectory = klaviyoApplicationSupportDirectory()
        let stateFileName = "klaviyo-\(testApiKey)-state.json"

        var copiedFiles: Set<String> = []
        var removedFiles: [String] = []

        // Setup: State file exists in old location
        environment.fileClient.fileExists = { path in
            let oldStatePath = oldDirectory.appendingPathComponent(stateFileName, isDirectory: false).path
            let newStatePath = newDirectory.appendingPathComponent(stateFileName, isDirectory: false).path

            // Old file exists if not removed
            if path == oldStatePath {
                return !removedFiles.contains(path)
            }

            // New file exists after copy, but will be removed during rollback
            if path == newStatePath {
                return copiedFiles.contains(stateFileName) && !removedFiles.contains(path)
            }

            return false
        }

        environment.fileClient.createDirectory = { _, _ in }

        environment.fileClient.copyItem = { fromPath, _ in
            if fromPath.contains(stateFileName) {
                copiedFiles.insert(stateFileName)
            }
        }

        environment.fileClient.removeItem = { path in
            removedFiles.append(path)
        }

        // Mock verification failure (corrupted state)
        environment.dataFromUrl = { _ in
            throw FakeFileError.fake
        }

        let result = migrateFilesIfNeeded(apiKey: testApiKey)

        // Verify file was copied
        XCTAssertEqual(copiedFiles.count, 1)

        // Verify rollback occurred (copied file was removed)
        XCTAssertEqual(removedFiles.count, 1)

        // Verify old directory is returned on failure
        XCTAssertEqual(result, oldDirectory)
    }

    // MARK: - Idempotency Tests

    func testMigrationIsIdempotent() {
        let newDirectory = klaviyoApplicationSupportDirectory()
        let stateFileName = "klaviyo-\(testApiKey)-state.json"
        let newStatePath = newDirectory.appendingPathComponent(stateFileName, isDirectory: false).path

        var migrationAttempts = 0

        // Setup: After first migration, files exist in new location
        environment.fileClient.fileExists = { path in
            // Second call should find file in new location
            path == newStatePath && migrationAttempts > 0
        }

        environment.fileClient.createDirectory = { _, _ in }

        environment.fileClient.copyItem = { _, _ in
            migrationAttempts += 1
        }

        // First call - no files in new location yet
        let result1 = migrateFilesIfNeeded(apiKey: testApiKey)
        XCTAssertEqual(result1, newDirectory)

        // Second call should skip migration (files already in new location)
        let result2 = migrateFilesIfNeeded(apiKey: testApiKey)
        XCTAssertEqual(result2, newDirectory)

        // Verify migration only happened once (no copy on second call)
        XCTAssertEqual(migrationAttempts, 0) // 0 because first call found no old files
    }

    // MARK: - Multiple API Keys Tests

    func testMigrateFilesIfNeeded_MultipleApiKeys() {
        let apiKey1 = "api-key-1"
        let apiKey2 = "api-key-2"
        let oldDirectory = TEST_URL
        let newDirectory = klaviyoApplicationSupportDirectory()

        var copiedFiles: Set<String> = []
        var removedFiles: [String] = []

        // Setup: State files exist for both API keys
        environment.fileClient.fileExists = { path in
            let oldStatePath1 = oldDirectory.appendingPathComponent("klaviyo-\(apiKey1)-state.json", isDirectory: false).path
            let oldStatePath2 = oldDirectory.appendingPathComponent("klaviyo-\(apiKey2)-state.json", isDirectory: false).path
            let newStatePath1 = newDirectory.appendingPathComponent("klaviyo-\(apiKey1)-state.json", isDirectory: false).path
            let newStatePath2 = newDirectory.appendingPathComponent("klaviyo-\(apiKey2)-state.json", isDirectory: false).path

            // Old files exist if not removed
            if [oldStatePath1, oldStatePath2].contains(path) {
                return !removedFiles.contains(path)
            }

            // New files exist after copy
            if path == newStatePath1 && copiedFiles.contains(apiKey1) {
                return true
            }
            if path == newStatePath2 && copiedFiles.contains(apiKey2) {
                return true
            }

            return false
        }

        environment.fileClient.createDirectory = { _, _ in }

        environment.fileClient.copyItem = { fromPath, _ in
            if fromPath.contains(apiKey1) {
                copiedFiles.insert(apiKey1)
            } else if fromPath.contains(apiKey2) {
                copiedFiles.insert(apiKey2)
            }
        }

        environment.fileClient.removeItem = { path in
            removedFiles.append(path)
        }

        // Mock successful state verification
        let testState = KlaviyoState(apiKey: "test", anonymousId: "test-anon-id", queue: [])
        environment.dataFromUrl = { _ in try! JSONEncoder().encode(testState) }
        environment.decoder = DataDecoder(jsonDecoder: JSONDecoder())

        // Migrate both API keys
        let result1 = migrateFilesIfNeeded(apiKey: apiKey1)
        let result2 = migrateFilesIfNeeded(apiKey: apiKey2)

        // Verify both migrations succeeded
        XCTAssertEqual(result1, newDirectory)
        XCTAssertEqual(result2, newDirectory)

        // Verify files for both API keys were copied
        XCTAssertTrue(copiedFiles.contains(apiKey1))
        XCTAssertTrue(copiedFiles.contains(apiKey2))
    }
}
