//
//  IdentityStorePersistenceTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

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
            fileName: StoreFile.identity
        )
        let store = IdentityStore()
        XCTAssertEqual(store.current.anonymousId, "existing")
    }

    func testUpdateWritesThroughProfileSynchronously() {
        let store = IdentityStore()
        _ = store.current // hydrate + mint
        store.update(ProfileData(email: "a@b.com", anonymousId: store.current.anonymousId))
        XCTAssertEqual(
            loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)?.profile.email,
            "a@b.com"
        )
    }

    func testPushTokenIsOwnedPersistedAndSurvivesProfileUpdate() {
        let store = IdentityStore()
        let token = PushTokenData(
            pushToken: "tok", pushEnablement: .authorized,
            pushBackground: .available, deviceData: DeviceMetadata(context: .test)
        )
        store.updatePushToken(token)
        store.update(ProfileData(email: "x@y.com", anonymousId: store.current.anonymousId))
        XCTAssertEqual(store.pushToken, token)
        XCTAssertEqual(loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)?.pushToken, token)
    }

    func testMintNewAnonymousIdIsPureAndCommitsViaUpdate() {
        // Start from a persisted, known anonymousId to prove the mint does not touch store state.
        savePersisted(
            PersistedIdentity(
                version: 1,
                profile: ProfileData(email: "keep@me.com", anonymousId: "old"),
                pushToken: nil
            ),
            fileName: StoreFile.identity
        )
        let store = IdentityStore()
        XCTAssertEqual(store.current.anonymousId, "old")

        // Subscribe AFTER hydration; only a genuine emission would deliver a new value here.
        var emissions: [ProfileData] = []
        let cancellable = store.publisher.dropFirst().sink { emissions.append($0) }
        defer { cancellable.cancel() }

        let minted = store.mintNewAnonymousId()

        XCTAssertEqual(minted, Self.mintedAnonId, "mint uses environment.uuid")
        // Pure: the mint mutates no store state, emits nothing, and persists nothing.
        XCTAssertEqual(store.current.anonymousId, "old", "mint does not mutate the store")
        XCTAssertEqual(store.current.email, "keep@me.com")
        XCTAssertTrue(emissions.isEmpty, "mint does not emit")
        XCTAssertEqual(
            loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)?.profile.anonymousId,
            "old", "mint does not persist; disk still carries the pre-mint anon"
        )

        // The caller commits via update: it persists + emits the final value exactly once.
        store.update(ProfileData(email: "keep@me.com", anonymousId: minted))
        XCTAssertEqual(emissions.count, 1, "update is the sole emission")
        XCTAssertEqual(emissions.last?.anonymousId, minted)
        XCTAssertEqual(
            loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)?.profile.anonymousId,
            minted, "update persists the minted anonymousId"
        )
    }

    // Push token minted anonymousId survives a token write (profile side survives token update).
    func testProfileSurvivesPushTokenUpdate() {
        let store = IdentityStore()
        let minted = store.current.anonymousId
        let token = PushTokenData(
            pushToken: "tok", pushEnablement: .authorized,
            pushBackground: .available, deviceData: DeviceMetadata(context: .test)
        )
        store.updatePushToken(token)
        XCTAssertEqual(store.current.anonymousId, minted)
        let onDisk = loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)
        XCTAssertEqual(onDisk?.profile.anonymousId, minted)
        XCTAssertEqual(onDisk?.pushToken, token)
    }

    // MARK: - Production file location

    func testUpdateRoutesIdentityFileToApplicationSupport() {
        let appSupportRoot = URL(fileURLWithPath: "/tmp/klaviyo-identity-tests/app-support")
        let libraryRoot = URL(fileURLWithPath: "/tmp/klaviyo-identity-tests/library")
        var capturedURL: URL?

        environment.fileClient = FileClient(
            write: { _, url in capturedURL = url },
            fileExists: { _ in false },
            removeItem: { _ in },
            libraryDirectory: { libraryRoot },
            applicationSupportDirectory: { appSupportRoot }
        )

        IdentityStore().update(ProfileData(anonymousId: "anon-1"))

        XCTAssertEqual(capturedURL, appSupportRoot.appendingPathComponent(StoreFile.identity))
        XCTAssertFalse(capturedURL?.path.hasPrefix(libraryRoot.path) ?? true)
    }

    // MARK: - Thread safety

    func testConcurrentAccessIsRaceFree() {
        let store = IdentityStore()
        _ = store.current // hydrate once up front
        let token = PushTokenData(
            pushToken: "tok", pushEnablement: .authorized,
            pushBackground: .available, deviceData: DeviceMetadata(context: .test)
        )
        // Hammer readers + writers concurrently. Writes are lock-serialized (so disk I/O through the
        // file double stays serialized); this catches races on `pushTokenValue` / `hydrated` under
        // the thread sanitizer and must not crash. The store must remain readable afterward.
        DispatchQueue.concurrentPerform(iterations: 2000) { i in
            switch i % 4 {
            case 0: store.update(ProfileData(email: "e\(i)@x.com", anonymousId: "anon-\(i)"))
            case 1: store.updatePushToken(i % 8 == 0 ? nil : token)
            case 2: _ = store.current
            default: _ = store.pushToken
            }
        }
        XCTAssertNotNil(store.current.anonymousId)
    }
}
