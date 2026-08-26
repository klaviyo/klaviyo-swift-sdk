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

    /// A queue-only file at this same path (the ongoing shape until MAGE-952) must not be
    /// mistaken for an unmigrated legacy blob.
    func testNoOpWhenFileIsQueueOnlyShape() throws {
        let apiKey = "queue-only-key"
        let queueOnlyState = KlaviyoState(queue: [legacyRequest("existing", apiKey: apiKey)])
        fakeEnvironment[klaviyoStateFile(apiKey: apiKey).path] = try JSONEncoder().encode(queueOnlyState)

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertNil(SDKConfigStore.shared.current.apiKey, "queue-only shape must not be treated as legacy")
        XCTAssertTrue(legacyFileExists(apiKey: apiKey), "left untouched for normal use")
    }

    // MARK: - Corrupt file

    func testCorruptFileFallsThroughWithoutTouchingStores() {
        let apiKey = "corrupt-key"
        fakeEnvironment[klaviyoStateFile(apiKey: apiKey).path] = Data("not json".utf8)

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertNil(SDKConfigStore.shared.current.apiKey)
        XCTAssertTrue(legacyFileExists(apiKey: apiKey),
                      "left for loadKlaviyoStateFromDisk's own corrupt-file handling")
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
                      "left in place — loadKlaviyoStateFromDisk still reads its queue as-is")
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
                      "left for loadKlaviyoStateFromDisk's own pre-existing mismatch guard")
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

    /// Regression: a `removeItem` failure after a fully-successful write+verify used to leave the
    /// legacy file in its original, still-legacy-shaped content — which `loadKlaviyoStateFromDisk`
    /// (called right after this) would then re-decode into `state.queue`, duplicating the same
    /// requests `restore` had just written to `QueueStore`. The file must be overwritten to
    /// queue-only-empty regardless of whether the actual removal succeeds.
    func testRemoveFailureStillRetiresLegacyContentAndDoesNotDuplicateQueue() throws {
        let apiKey = "remove-fail-key"
        try seedLegacyFile(apiKey: apiKey, fixture: LegacyNestedFixture(
            apiKey: apiKey, identity: ProfileData(anonymousId: "anon-remove-fail"), pushTokenData: nil,
            queue: [legacyRequest("a", apiKey: apiKey)]
        ))
        fakeEnvironment.failRemoveForPathSuffix = "-state.json"

        migrateLegacyStateIfNeeded(apiKey: apiKey)

        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anon-remove-fail")
        XCTAssertEqual(QueueStore.store(for: apiKey).requests.map(\.id), ["a"])

        // The remove failed, so the path still exists — but its content must no longer be
        // legacy-shaped, or a later loadKlaviyoStateFromDisk read would duplicate the queue.
        XCTAssertTrue(legacyFileExists(apiKey: apiKey), "removeItem was injected to fail")
        let remaining = try JSONDecoder().decode(
            KlaviyoState.self, from: fakeEnvironment[klaviyoStateFile(apiKey: apiKey).path]!
        )
        XCTAssertNil(remaining.apiKey, "overwritten to queue-only shape despite the failed removal")
        XCTAssertEqual(remaining.queue, [], "must not carry the requests already restored to QueueStore")
    }

    // MARK: - Transient failure recovers within the same call

    /// `loadKlaviyoStateFromDisk` and the debounced state-save both keep writing this same file
    /// path once initialized, normalizing it to queue-only within ~1s of a settled init — so a
    /// transient failure must recover via migration's own in-call retries, not by surviving to a
    /// future cold launch that will never actually see the legacy shape again.
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
