// Tests/KlaviyoCoreTests/StorePersistenceTests.swift
import XCTest
@testable import KlaviyoCore

final class StorePersistenceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        environment = FileIODouble.make()
    }

    override func tearDown() {
        FileIODouble.reset()
        environment = KlaviyoEnvironment.production
        super.tearDown()
    }

    func testSaveThenLoadRoundTripsIdentity() {
        let identity = PersistedIdentity(
            version: PersistedIdentity.currentVersion,
            profile: ProfileData(email: "a@b.com", anonymousId: "anon-1"),
            pushToken: nil
        )
        savePersisted(identity, fileName: StoreFile.identity)
        let loaded = loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)
        XCTAssertEqual(loaded, identity)
    }

    func testLoadReturnsNilWhenFileAbsent() {
        XCTAssertNil(loadPersisted(PersistedConfig.self, fileName: StoreFile.config))
    }

    func testPersistedIdentityJSONCarriesVersionKey() throws {
        let identity = PersistedIdentity(version: 1, profile: ProfileData(), pushToken: nil)
        let json = try environment.encodeJSON(identity)
        let jsonObj = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(jsonObj?["version"] as? Int, 1)
    }
}
