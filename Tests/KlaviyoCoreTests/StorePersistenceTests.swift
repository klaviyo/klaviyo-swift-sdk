//
//  StorePersistenceTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

@testable import KlaviyoCore
import XCTest

final class StorePersistenceTests: XCTestCase {
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

    /// There is no `directory` override any more — every persisted store file must land under
    /// Application Support, even when it differs from the library root.
    func testSaveAndLoadAlwaysRouteToApplicationSupport() {
        assertWriteRoutesToApplicationSupport(fileName: StoreFile.config) {
            savePersisted(PersistedConfig(version: 1, apiKey: "pk-1"), fileName: StoreFile.config)
        }
    }

    func testPersistedIdentityJSONCarriesVersionKey() throws {
        let identity = PersistedIdentity(version: 1, profile: ProfileData(), pushToken: nil)
        let json = try environment.encodeJSON(identity)
        let jsonObj = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(jsonObj?["version"] as? Int, 1)
    }
}
