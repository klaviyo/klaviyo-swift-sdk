//
//  LegacyStateMigrationTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import Foundation
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift

/// Legacy shape with nested `identity`. Not `private` — reused by `StateManagementTests`.
struct LegacyNestedFixture: Encodable {
    var apiKey: String?
    var identity: ProfileData
    var pushTokenData: PushTokenData?
    var queue: [KlaviyoRequest]
}

/// Legacy shape with identity flattened at the top level — exercises `LegacyCodingKeys`.
private struct LegacyFlatFixture: Encodable {
    var apiKey: String?
    var email: String?
    var anonymousId: String?
    var phoneNumber: String?
    var externalId: String?
    var pushTokenData: PushTokenData?
    var queue: [KlaviyoRequest]
}

final class LegacyStateMigrationTests: XCTestCase {
    private var fakeEnvironment: InMemoryEnvironment!

    override func setUp() {
        super.setUp()
        fakeEnvironment = InMemoryEnvironment(
            libraryRoot: URL(fileURLWithPath: "/tmp/klaviyo-migration-tests/library"),
            appSupportRoot: URL(fileURLWithPath: "/tmp/klaviyo-migration-tests/app-support")
        )
        environment = fakeEnvironment.makeEnvironment()
        resetCanonicalCoreStores()
        QueueStore.resetRegistry()
    }

    override func tearDown() {
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        QueueStore.resetRegistry()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func legacyRequest(
        _ id: String, apiKey: String, at date: Date = Date(timeIntervalSince1970: 0)
    ) -> KlaviyoRequest {
        KlaviyoRequest(
            id: id, endpoint: .fetchGeofences(apiKey, latitude: nil, longitude: nil), enqueuedAt: date
        )
    }

    private func testPushToken(_ token: String = "push-token") -> PushTokenData {
        PushTokenData(
            pushToken: token,
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        )
    }

    private func seedLegacyFile(apiKey: String, fixture: some Encodable) throws {
        let data = try JSONEncoder().encode(fixture)
        fakeEnvironment[klaviyoStateFile(apiKey: apiKey).path] = data
    }

    private func legacyFileExists(apiKey: String) -> Bool {
        environment.fileClient.fileExists(klaviyoStateFile(apiKey: apiKey).path)
    }

    // MARK: - No-op paths

    func testNoOpWhenLegacyFileAbsent() {
        migrateLegacyStateIfNeeded(apiKey: "fresh-install-key")
        XCTAssertNil(SDKConfigStore.shared.current.apiKey)
    }

    /// The ongoing (post-migration) state-blob file at this same path — which no longer carries
    /// identity/apiKey — must not be mistaken for an unmigrated legacy blob.
    func testNoOpWhenFileIsCurrentStateBlobShape() throws {
        let apiKey = "queue-only-key"
        // `KlaviyoState` is no longer Codable; simulate the post-migration blob (empty JSON object,
        // no apiKey) that the SDK previously wrote via `saveKlaviyoState`.
        let currentBlobData = Data("{}".utf8)
        fakeEnvironment[klaviyoStateFile(apiKey: apiKey).path] = currentBlobData

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertNil(
            SDKConfigStore.shared.current.apiKey,
            "current state-blob shape must not be treated as legacy"
        )
        XCTAssertTrue(legacyFileExists(apiKey: apiKey), "left untouched for normal use")
    }

    // MARK: - Corrupt file

    func testCorruptFileFallsThroughWithoutTouchingStores() {
        let apiKey = "corrupt-key"
        fakeEnvironment[klaviyoStateFile(apiKey: apiKey).path] = Data("not json".utf8)

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertNil(SDKConfigStore.shared.current.apiKey)
        XCTAssertTrue(legacyFileExists(apiKey: apiKey),
                      "left in place — corrupt blobs fall through without touching stores")
    }

    /// apiKey present but identity matches neither known shape, so anonymousId is nil — must not
    /// be trusted; a real legacy blob always has one.
    func testUnrecognizedIdentityShapeFallsThroughWithoutTouchingStores() throws {
        let apiKey = "unrecognized-shape-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyFlatFixture(
            apiKey: apiKey, email: nil, anonymousId: nil, phoneNumber: nil, externalId: nil,
            pushTokenData: nil, queue: [legacyRequest("a", apiKey: apiKey)]
        ))

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertNil(SDKConfigStore.shared.current.apiKey, "no store should be touched")
        XCTAssertEqual(QueueStore.store(for: apiKey).requests, [])
        XCTAssertTrue(legacyFileExists(apiKey: apiKey),
                      "left in place — unrecognized shapes fall through without touching stores")
    }

    // MARK: - Happy path

    func testHappyPathFlatLegacyShapeMigratesAllFields() throws {
        let apiKey = "flat-key"
        let pushToken = testPushToken()
        let queue = [legacyRequest("a", apiKey: apiKey), legacyRequest("b", apiKey: apiKey)]
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyFlatFixture(
            apiKey: apiKey, email: "a@b.com", anonymousId: "anon-flat",
            phoneNumber: "+15551234567", externalId: "ext-1", pushTokenData: pushToken, queue: queue
        ))

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)
        XCTAssertEqual(IdentityStore.shared.current.email, "a@b.com")
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anon-flat", "upgrade preserves anonymousId")
        XCTAssertEqual(IdentityStore.shared.current.phoneNumber, "+15551234567")
        XCTAssertEqual(IdentityStore.shared.current.externalId, "ext-1")
        XCTAssertEqual(IdentityStore.shared.pushToken, pushToken, "upgrade preserves the push token")
        XCTAssertEqual(QueueStore.store(for: apiKey).requests.map(\.id), ["a", "b"],
                       "upgrade preserves the full queue backlog, in order")
        XCTAssertFalse(legacyFileExists(apiKey: apiKey), "legacy file retired on success")
    }

    func testHappyPathNestedIdentityShapeMigratesAllFields() throws {
        let apiKey = "nested-key"
        let pushToken = testPushToken()
        let queue = [
            legacyRequest("a", apiKey: apiKey),
            legacyRequest("b", apiKey: apiKey),
            legacyRequest("c", apiKey: apiKey)
        ]
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey,
            identity: ProfileData(
                email: "nested@b.com", phoneNumber: "+15559876543",
                externalId: "ext-2", anonymousId: "anon-nested"
            ),
            pushTokenData: pushToken,
            queue: queue
        ))

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anon-nested")
        XCTAssertEqual(IdentityStore.shared.current.email, "nested@b.com")
        XCTAssertEqual(IdentityStore.shared.pushToken, pushToken)
        XCTAssertEqual(QueueStore.store(for: apiKey).requests.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(legacyFileExists(apiKey: apiKey))
    }

    func testEmptyLegacyQueueMigratesCleanlyNotSkippedAsAbsent() throws {
        let apiKey = "empty-clean-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-clean"), pushTokenData: nil, queue: []
        ))

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)
        XCTAssertEqual(QueueStore.store(for: apiKey).requests, [])
        XCTAssertFalse(legacyFileExists(apiKey: apiKey),
                       "genuine success removes the legacy file even for an empty queue")
    }

    func testOversizedLegacyQueueMigratesAsIsWithoutTruncating() throws {
        let apiKey = "oversized-key"
        let queue = (0..<(QueueStore.maxQueueSize + 10)).map {
            legacyRequest("req-\($0)", apiKey: apiKey, at: Date(timeIntervalSince1970: TimeInterval($0)))
        }
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-big"), pushTokenData: nil, queue: queue
        ))

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertEqual(QueueStore.store(for: apiKey).count, QueueStore.maxQueueSize + 10,
                       "migration itself does not truncate — self-heals on the next real enqueue")
        XCTAssertFalse(legacyFileExists(apiKey: apiKey))
    }

    // MARK: - Cross-company mismatch

    func testCrossCompanyMismatchDoesNotMigrate() throws {
        let fileApiKey = "company-b"
        try seedLegacyFile(apiKey: fileApiKey, fixture: LegacyNestedFixture(
            apiKey: "company-a", identity: ProfileData(anonymousId: "anon-a"), pushTokenData: nil,
            queue: [legacyRequest("a", apiKey: "company-a")]
        ))

        migrateLegacyStateIfNeeded(apiKey: fileApiKey)

        XCTAssertNil(SDKConfigStore.shared.current.apiKey,
                     "company A's data must not be adopted under company B's init")
        XCTAssertEqual(QueueStore.store(for: fileApiKey).requests, [],
                       "company A's queue must not leak into company B's store")
        XCTAssertTrue(legacyFileExists(apiKey: fileApiKey),
                      "left in place — cross-company mismatch falls through without touching stores")
    }

    // MARK: - Verify-then-delete: per-store fault injection

    func testConfigWriteFailureLeavesLegacyFileThenCompletesOnRetry() throws {
        let apiKey = "config-fail-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-cfg"), pushTokenData: nil,
            queue: [legacyRequest("a", apiKey: apiKey)]
        ))
        fakeEnvironment.failWriteForPathSuffix = "klaviyo-config.json"

        migrateLegacyStateIfNeeded(apiKey: apiKey)
        XCTAssertTrue(legacyFileExists(apiKey: apiKey),
                      "config write failed — verification must catch it and keep the legacy file")

        fakeEnvironment.failWriteForPathSuffix = nil // "fix the disk" before retrying
        QueueStore.resetRegistry()
        migrateLegacyStateIfNeeded(apiKey: apiKey) // retry, same untouched legacy source
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)
        XCTAssertEqual(QueueStore.store(for: apiKey).requests.map(\.id), ["a"],
                       "no duplicates from the retry")
        XCTAssertFalse(legacyFileExists(apiKey: apiKey))
    }

    func testIdentityWriteFailureLeavesLegacyFileThenCompletesOnRetry() throws {
        let apiKey = "identity-fail-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-id"), pushTokenData: nil,
            queue: [legacyRequest("a", apiKey: apiKey)]
        ))
        fakeEnvironment.failWriteForPathSuffix = "klaviyo-identity.json"

        migrateLegacyStateIfNeeded(apiKey: apiKey)
        // IdentityStore.update() swallows the write failure; the legacy file staying put is what
        // proves the independent from-disk verification caught it.
        XCTAssertTrue(legacyFileExists(apiKey: apiKey),
                      "identity write failed — verification must catch it and keep the legacy file")

        fakeEnvironment.failWriteForPathSuffix = nil // "fix the disk" before retrying
        QueueStore.resetRegistry()
        migrateLegacyStateIfNeeded(apiKey: apiKey)
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anon-id")
        XCTAssertEqual(QueueStore.store(for: apiKey).requests.map(\.id), ["a"])
        XCTAssertFalse(legacyFileExists(apiKey: apiKey))
    }

    func testQueueWriteFailureLeavesLegacyFileThenCompletesOnRetryWithoutDuplicates() throws {
        let apiKey = "queue-fail-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-q"), pushTokenData: nil,
            queue: [legacyRequest("a", apiKey: apiKey), legacyRequest("b", apiKey: apiKey)]
        ))
        fakeEnvironment.failWriteForPathSuffix = "-queue.json"

        migrateLegacyStateIfNeeded(apiKey: apiKey)
        // Config + identity succeed (queue is written last); queue write fails → legacy file stays.
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anon-q")
        XCTAssertTrue(legacyFileExists(apiKey: apiKey))

        fakeEnvironment.failWriteForPathSuffix = nil // "fix the disk" before retrying
        QueueStore.resetRegistry()
        migrateLegacyStateIfNeeded(apiKey: apiKey) // retry from the untouched legacy source
        XCTAssertEqual(QueueStore.store(for: apiKey).requests.map(\.id), ["a", "b"],
                       "no duplicates from the retry")
        XCTAssertFalse(legacyFileExists(apiKey: apiKey))
    }

    /// Closes the hole `QueueStore.restore`'s throwing signature exists for: an empty queue and a
    /// failed load both read back as `[]`, so read-back alone can't catch this failure.
    func testEmptyLegacyQueueWithInjectedWriteFailureDoesNotFalselyVerify() throws {
        let apiKey = "empty-queue-fail-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-empty-fail"),
            pushTokenData: nil, queue: []
        ))
        fakeEnvironment.failWriteForPathSuffix = "-queue.json"

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertTrue(legacyFileExists(apiKey: apiKey),
                      "an empty queue write failure must still block deletion, not falsely verify as success")
    }

    /// Regression guard (cursor bugbot "Migration retry wipes live queue"): when `removeItem` fails
    /// after a successful write+verify, the legacy file must be NEUTRALIZED (overwritten to an
    /// apiKey-less shape), never left legacy-shaped. `QueueStore` is now the flush source and
    /// accumulates live requests after init; a re-migration would wholesale-`restore` over it and
    /// drop everything enqueued since. So a future launch must see the file as already-migrated.
    func testRemoveFailureNeutralizesLegacyFileSoReMigrationCannotWipeLiveQueue() throws {
        let apiKey = "remove-fail-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-remove-fail"), pushTokenData: nil,
            queue: [legacyRequest("a", apiKey: apiKey)]
        ))
        fakeEnvironment.failRemoveForPathSuffix = "-state.json"

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        // Stores fully populated despite the failed removal.
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anon-remove-fail")
        XCTAssertEqual(QueueStore.store(for: apiKey).requests.map(\.id), ["a"])

        // A live request accumulates in the (now canonical) QueueStore after init.
        QueueStore.store(for: apiKey).enqueue(legacyRequest("live", apiKey: apiKey), persist: .synchronous)

        // Next cold launch: registry cleared (queue file persists). Migration must be a NO-OP —
        // the legacy file was neutralized — so the live request is NOT wiped by a re-`restore`.
        QueueStore.resetRegistry()
        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertEqual(
            QueueStore.store(for: apiKey).requests.map(\.id), ["a", "live"],
            "neutralized legacy file must not be re-migrated; the live queue must be preserved"
        )
    }

    /// Regression (cursor bugbot "Migration verify rejects merged live queue"): a request that
    /// raced into the QueueStore during the init window must not make verification fail. `restore`
    /// merge-prepends the legacy backlog and `verifyMigration` checks it as a PREFIX, so migration
    /// still succeeds, retires the legacy file, and preserves the windowed request.
    func testMigrationSucceedsWhenQueueAlreadyHasAWindowedRequest() throws {
        let apiKey = "windowed-verify-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-windowed"), pushTokenData: nil,
            queue: [legacyRequest("legacy-a", apiKey: apiKey)]
        ))
        // A request raced into the QueueStore before migration ran (early apiKey commit + an
        // init-window enqueue such as a geofence event or create(event:)).
        QueueStore.store(for: apiKey).enqueue(legacyRequest("windowed", apiKey: apiKey), persist: .synchronous)

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        // Verification passed despite the extra request → stores populated and the file retired.
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anon-windowed")
        XCTAssertFalse(legacyFileExists(apiKey: apiKey),
                       "migration must retire the legacy file even with a windowed request present")
        // Merge-prepend: legacy backlog in front, the windowed request preserved after.
        XCTAssertEqual(QueueStore.store(for: apiKey).requests.map(\.id), ["legacy-a", "windowed"])
    }

    // MARK: - Transient failure recovers within the same call

    /// A transient queue-write failure must recover via migration's own in-call retries; it must not
    /// survive to a future cold launch that will never actually see the legacy shape again.
    func testTransientQueueWriteFailureRecoversWithinTheSameCall() throws {
        let apiKey = "transient-fail-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-transient"), pushTokenData: nil,
            queue: [legacyRequest("a", apiKey: apiKey)]
        ))
        fakeEnvironment.transientFailure = (suffix: "-queue.json", remaining: 2)

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anon-transient")
        XCTAssertEqual(QueueStore.store(for: apiKey).requests.map(\.id), ["a"])
        XCTAssertFalse(legacyFileExists(apiKey: apiKey), "recovered without needing a second launch")
    }

    // MARK: - Resume a partially-completed migration

    /// Config and identity already correct (as if a prior run wrote them, then crashed before the
    /// queue write). A retry must complete cleanly without changing what's already right.
    func testResumePartiallyCompletedMigration() throws {
        let apiKey = "resume-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-resume"), pushTokenData: nil,
            queue: [legacyRequest("a", apiKey: apiKey), legacyRequest("b", apiKey: apiKey)]
        ))

        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-resume"))

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anon-resume")
        XCTAssertEqual(QueueStore.store(for: apiKey).requests.map(\.id), ["a", "b"])
        XCTAssertFalse(legacyFileExists(apiKey: apiKey))
    }
}
