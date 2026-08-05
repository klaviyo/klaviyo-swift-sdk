// Tests/KlaviyoCoreTests/CanonicalStoreUngatedTests.swift
//
// Integration coverage for the two ungated canonical-store behaviors:
//   1. Fresh install (no files) — IdentityStore mints, SDKConfigStore stays empty.
//   2. Relaunch (files present) — both stores hydrate before any initialize() call.
//
// These prove that Forms/Location can read identity + apiKey without KlaviyoSwift init.
//
@testable import KlaviyoCore
import XCTest

final class CanonicalStoreUngatedTests: XCTestCase {
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

    // MARK: - Fresh install (launch 1, no persisted files, no initialize)

    func testStoresReadableWithoutInitialize() throws {
        // Fresh install, launch 1: no files → IdentityStore mints, ConfigStore empty.
        let identity = IdentityStore()
        let config = SDKConfigStore()
        let anonymousId = try XCTUnwrap(identity.current.anonymousId) // minted ungated
        XCTAssertFalse(anonymousId.isEmpty)
        XCTAssertNotNil(UUID(uuidString: anonymousId)) // minted value is a valid UUID
        XCTAssertNil(config.current.apiKey)            // config never self-mints
    }

    // MARK: - Relaunch (launch 2, files present, no initialize)

    func testIdentityAndApiKeyVisibleBeforeInitializeOnRelaunch() {
        // Seed persisted files as if a prior launch had already run initialize().
        savePersisted(
            PersistedConfig(version: 1, apiKey: "pk-1"),
            fileName: StoreFile.config)
        savePersisted(
            PersistedIdentity(version: 1, profile: ProfileData(anonymousId: "anon-1"), pushToken: nil),
            fileName: StoreFile.identity)

        // Both stores hydrate from disk with no initialize() call.
        XCTAssertEqual(SDKConfigStore().current.apiKey, "pk-1")
        XCTAssertEqual(IdentityStore().current.anonymousId, "anon-1")
    }
}
