//
//  ProfilePropertyBufferTests.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/11/26.
//

@testable import KlaviyoCore
import AnyCodable
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import XCTest

final class ProfilePropertyBufferTests: XCTestCase {
    private var getRequests: () -> [KlaviyoRequest] = { [] }

    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        // Wire a spy QueueStore so we can observe enqueued requests without disk I/O.
        getRequests = seedTestQueueStore()
        // Ensure the buffer itself is empty before each test.
        ProfilePropertyBuffer.shared.reset()
    }

    override func tearDown() {
        ProfilePropertyBuffer.shared.reset()
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        environment = KlaviyoEnvironment.test()
        super.tearDown()
    }

    // MARK: - No-op when empty

    func testFlushWithEmptyBufferEnqueuesNothing() async {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-test"))
        await ProfilePropertyBuffer.shared.flushIntoQueue()
        XCTAssertEqual(getRequests().count, 0, "empty buffer must not enqueue any request")
    }

    // MARK: - Profile path (no push token)

    func testStageAndFlushEnqueuesOneCreateProfileRequest() async {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-test"))
        IdentityStore.shared.mutate {
            $0.email = "ada@example.com"
            $0.anonymousId = "anon-42"
        }

        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Ada"))
        ProfilePropertyBuffer.shared.stage(.lastName, AnyEncodable("Lovelace"))

        await ProfilePropertyBuffer.shared.flushIntoQueue()

        let requests = getRequests()
        XCTAssertEqual(requests.count, 1, "exactly one request must be enqueued")

        guard case let .createProfile(apiKey, payload) = requests[0].endpoint else {
            return XCTFail("expected .createProfile endpoint, got \(requests[0].endpoint)")
        }
        XCTAssertEqual(apiKey, "pk-test")
        XCTAssertEqual(payload.data.attributes.email, "ada@example.com")
        XCTAssertEqual(payload.data.attributes.anonymousId, "anon-42")
        XCTAssertEqual(payload.data.attributes.firstName, "Ada")
        XCTAssertEqual(payload.data.attributes.lastName, "Lovelace")
    }

    func testStagedCustomPropertiesFoldedIntoCreateProfile() async {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-test"))
        IdentityStore.shared.mutate { $0.anonymousId = "anon-1" }

        ProfilePropertyBuffer.shared.stage(.custom(customKey: "plan"), AnyEncodable("premium"))

        await ProfilePropertyBuffer.shared.flushIntoQueue()

        let requests = getRequests()
        XCTAssertEqual(requests.count, 1)
        guard case let .createProfile(_, payload) = requests[0].endpoint else {
            return XCTFail("expected .createProfile endpoint")
        }
        let props = payload.data.attributes.properties.value as? [String: Any]
        XCTAssertEqual(props?["plan"] as? String, "premium")
    }

    func testCanonicalIdentityIsUsedNotStaleSnapshot() async {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-test"))
        // Set identity AFTER staging to verify flush reads from IdentityStore, not a stale copy.
        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Charles"))
        IdentityStore.shared.mutate {
            $0.email = "charles@example.com"
            $0.anonymousId = "anon-99"
        }

        await ProfilePropertyBuffer.shared.flushIntoQueue()

        let requests = getRequests()
        XCTAssertEqual(requests.count, 1)
        guard case let .createProfile(_, payload) = requests[0].endpoint else {
            return XCTFail("expected .createProfile endpoint")
        }
        XCTAssertEqual(payload.data.attributes.email, "charles@example.com")
        XCTAssertEqual(payload.data.attributes.anonymousId, "anon-99")
        XCTAssertEqual(payload.data.attributes.firstName, "Charles")
    }

    // MARK: - Buffer cleared after flush

    func testBufferIsClearedAfterFlush() async {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-test"))
        IdentityStore.shared.mutate { $0.anonymousId = "anon-1" }

        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Flush"))

        await ProfilePropertyBuffer.shared.flushIntoQueue()
        // First flush: 1 request
        XCTAssertEqual(getRequests().count, 1)

        // Second flush with no new staged props: must be a no-op
        await ProfilePropertyBuffer.shared.flushIntoQueue()
        XCTAssertEqual(getRequests().count, 1, "second flush on cleared buffer must not enqueue again")
    }

    // MARK: - Push-token path

    func testFlushWithPushTokenEnqueuesRegisterPushToken() async {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-test"))
        IdentityStore.shared.mutate {
            $0.email = "grace@example.com"
            $0.anonymousId = "anon-7"
        }
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: "device-abc",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: .init(context: environment.appContextInfo())
        ))

        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Grace"))
        ProfilePropertyBuffer.shared.stage(.lastName, AnyEncodable("Hopper"))

        await ProfilePropertyBuffer.shared.flushIntoQueue()

        let requests = getRequests()
        XCTAssertEqual(requests.count, 1, "exactly one request for push-token path")

        guard case let .registerPushToken(apiKey, payload) = requests[0].endpoint else {
            return XCTFail("expected .registerPushToken endpoint, got \(requests[0].endpoint)")
        }
        XCTAssertEqual(apiKey, "pk-test")
        XCTAssertEqual(payload.data.attributes.token, "device-abc")
        // Structured attributes must be folded into the embedded profile.
        let embeddedProfile = payload.data.attributes.profile.data.attributes
        XCTAssertEqual(embeddedProfile.email, "grace@example.com")
        XCTAssertEqual(embeddedProfile.firstName, "Grace")
        XCTAssertEqual(embeddedProfile.lastName, "Hopper")
    }

    func testFlushWithPushTokenClearsBuffer() async {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-test"))
        IdentityStore.shared.mutate { $0.anonymousId = "anon-1" }
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: "device-abc",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: .init(context: environment.appContextInfo())
        ))

        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Staged"))
        await ProfilePropertyBuffer.shared.flushIntoQueue()
        XCTAssertEqual(getRequests().count, 1)

        // Second flush — buffer must be empty.
        await ProfilePropertyBuffer.shared.flushIntoQueue()
        XCTAssertEqual(getRequests().count, 1, "buffer must be cleared after push-token flush")
    }

    // MARK: - Location fold

    func testLocationPropertiesFoldedCorrectly() async {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-test"))
        IdentityStore.shared.mutate { $0.anonymousId = "anon-1" }

        ProfilePropertyBuffer.shared.stage(.city, AnyEncodable("Boston"))
        ProfilePropertyBuffer.shared.stage(.country, AnyEncodable("USA"))
        ProfilePropertyBuffer.shared.stage(.zip, AnyEncodable("02101"))

        await ProfilePropertyBuffer.shared.flushIntoQueue()

        let requests = getRequests()
        XCTAssertEqual(requests.count, 1)
        guard case let .createProfile(_, payload) = requests[0].endpoint else {
            return XCTFail("expected .createProfile endpoint")
        }
        let loc = payload.data.attributes.location
        XCTAssertNotNil(loc, "location must be present after staging location props")
        XCTAssertEqual(loc?.city, "Boston")
        XCTAssertEqual(loc?.country, "USA")
        XCTAssertEqual(loc?.zip, "02101")
    }

    // MARK: - No-op without apiKey

    func testFlushWithoutApiKeyIsNoOp() async {
        // No SDKConfigStore.shared.update — apiKey is nil.
        IdentityStore.shared.mutate { $0.anonymousId = "anon-1" }
        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Nobody"))

        await ProfilePropertyBuffer.shared.flushIntoQueue()

        XCTAssertEqual(getRequests().count, 0, "no request must be enqueued when apiKey is absent")
    }

    // MARK: - Stage from multiple callers (thread safety smoke test)

    func testConcurrentStagesDontLoseUpdates() async {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-test"))
        IdentityStore.shared.mutate { $0.anonymousId = "anon-1" }

        // Stage many distinct keys from genuinely concurrent threads. The `NSLock` is the
        // thread-safety boundary under test: without it the shared dict would race and drop
        // entries. `concurrentPerform` blocks until every stage completes, so the flush below
        // sees the full set.
        let count = 200
        DispatchQueue.concurrentPerform(iterations: count) { i in
            ProfilePropertyBuffer.shared.stage(.custom(customKey: "k\(i)"), AnyEncodable("v\(i)"))
        }

        await ProfilePropertyBuffer.shared.flushIntoQueue()

        guard case let .createProfile(_, payload) = getRequests().first?.endpoint else {
            return XCTFail("expected .createProfile endpoint")
        }
        let props = payload.data.attributes.properties.value as? [String: Any]
        // Every concurrently-staged property must survive — none dropped by a lost update.
        for i in 0..<count {
            XCTAssertEqual(props?["k\(i)"] as? String, "v\(i)", "property k\(i) was lost")
        }
    }

    // MARK: - Reset clears staged properties

    // Regression guard: staged properties must NOT survive a profile reset (resetProfile / company
    // switch / profile-clobber). `KlaviyoState.reset()` clears the buffer; without that, staged
    // properties leak onto the next identity on the following flush.
    func testKlaviyoStateResetDropsStagedProperties() async {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-test"))
        IdentityStore.shared.mutate { $0.anonymousId = "anon-1" }
        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Ghost"))

        // Reset the profile — this must drop the staged property.
        var state = KlaviyoState(apiKey: "pk-test", anonymousId: "anon-1", initalizationState: .initialized)
        state.reset()

        // A drain now finds an empty buffer, so nothing carrying the staged property is enqueued.
        await ProfilePropertyBuffer.shared.flushIntoQueue()
        XCTAssertTrue(
            getRequests().isEmpty,
            "staged properties must be cleared on reset, not leak onto the next identity"
        )
    }
}
