// Tests/KlaviyoCoreTests/IdentityStorePersistenceTests.swift
@testable import KlaviyoCore
import Combine
import XCTest

final class IdentityStorePersistenceTests: XCTestCase {
    private var fileIO: FileIODouble!

    private static let mintedAnonId = "00000000-0000-0000-0000-0000000000AA"

    override func setUp() {
        super.setUp()
        fileIO = FileIODouble()
        environment = fileIO.makeEnvironment()
        environment.uuid = { UUID(uuidString: Self.mintedAnonId)! }
    }

    override func tearDown() {
        environment = KlaviyoEnvironment.test()
        fileIO = nil
        super.tearDown()
    }

    func testMintsAnonymousIdOnFirstAccessWithoutInitialize() {
        let store = IdentityStore()
        XCTAssertEqual(store.current.anonymousId, Self.mintedAnonId)
        // Persisted so it survives relaunch:
        let onDisk = loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)
        XCTAssertEqual(onDisk?.profile.anonymousId, Self.mintedAnonId)
    }

    func testDoesNotReMintWhenAnonymousIdPersisted() {
        savePersisted(
            PersistedIdentity(version: 1, profile: ProfileData(anonymousId: "existing"), pushToken: nil),
            fileName: StoreFile.identity)
        let store = IdentityStore()
        XCTAssertEqual(store.current.anonymousId, "existing")
    }

    func testUpdateWritesThroughProfileSynchronously() {
        let store = IdentityStore()
        _ = store.current // hydrate + mint
        store.update(ProfileData(email: "a@b.com", anonymousId: store.current.anonymousId))
        XCTAssertEqual(
            loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)?.profile.email,
            "a@b.com")
    }

    func testPushTokenIsOwnedPersistedAndSurvivesProfileUpdate() {
        let store = IdentityStore()
        let token = PushTokenData(
            pushToken: "tok", pushEnablement: .authorized,
            pushBackground: .available, deviceData: DeviceMetadata(context: .test))
        store.updatePushToken(token)
        store.update(ProfileData(email: "x@y.com", anonymousId: store.current.anonymousId))
        XCTAssertEqual(store.pushToken, token)
        XCTAssertEqual(loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)?.pushToken, token)
    }

    func testMintNewAnonymousIdReplacesPersistsAndEmits() {
        // Start from a persisted, known anonymousId so we can observe the mint replacing it.
        savePersisted(
            PersistedIdentity(version: 1, profile: ProfileData(email: "keep@me.com", anonymousId: "old"), pushToken: nil),
            fileName: StoreFile.identity)
        let store = IdentityStore()
        XCTAssertEqual(store.current.anonymousId, "old")

        var emitted: ProfileData?
        let cancellable = store.publisher.sink { emitted = $0 }
        defer { cancellable.cancel() }

        let minted = store.mintNewAnonymousId()

        XCTAssertEqual(minted, Self.mintedAnonId, "mint uses environment.uuid")
        XCTAssertEqual(store.current.anonymousId, minted, "in-memory value updated")
        XCTAssertEqual(store.current.email, "keep@me.com", "other identity fields are preserved")
        XCTAssertEqual(emitted?.anonymousId, minted, "subscribers receive the new anonymousId")
        XCTAssertEqual(
            loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)?.profile.anonymousId,
            minted, "minted anonymousId is persisted")
    }

    // Push token minted anonymousId survives a token write (profile side survives token update).
    func testProfileSurvivesPushTokenUpdate() {
        let store = IdentityStore()
        let minted = store.current.anonymousId
        let token = PushTokenData(
            pushToken: "tok", pushEnablement: .authorized,
            pushBackground: .available, deviceData: DeviceMetadata(context: .test))
        store.updatePushToken(token)
        XCTAssertEqual(store.current.anonymousId, minted)
        let onDisk = loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)
        XCTAssertEqual(onDisk?.profile.anonymousId, minted)
        XCTAssertEqual(onDisk?.pushToken, token)
    }
}
