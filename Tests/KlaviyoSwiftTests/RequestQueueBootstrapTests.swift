//
//  RequestQueueBootstrapTests.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/11/26.
//

@testable import KlaviyoCore
import AnyCodable
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import XCTest

final class RequestQueueBootstrapTests: XCTestCase {
    private var savedSwiftEnvironment: KlaviyoSwiftEnvironment!

    override func setUp() {
        super.setUp()
        savedSwiftEnvironment = klaviyoSwiftEnvironment
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        ProfilePropertyBuffer.shared.reset()
        seedTestQueueStore()
    }

    override func tearDown() {
        ProfilePropertyBuffer.shared.reset()
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = savedSwiftEnvironment
        super.tearDown()
    }

    // The `RequestQueue` exposed via `klaviyoSwiftEnvironment` must be reachable AND wired with a
    // `willDrain` that flushes `ProfilePropertyBuffer` into the queue. Driving the env-reachable
    // queue end-to-end (rather than a locally-built one) proves the bootstrap wiring: `willDrain`
    // → `flushIntoQueue` → enqueue → send. The `.test()` factory mirrors production's `send`/
    // `willDrain`, so the transport is observed through the standard `environment.klaviyoAPI` stub.
    func testEnvironmentRequestQueueWillDrainFlushesProfileProperties() async {
        let sentRequests = ThreadSafeBox<[KlaviyoRequest]>([])
        environment.klaviyoAPI.send = { request, _ in
            sentRequests.mutate { $0.append(request) }
            return .success(Data())
        }

        // apiKey + anonymousId so flushIntoQueue doesn't no-op.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-bootstrap-test"))
        IdentityStore.shared.mutate { $0.anonymousId = "anon-bootstrap" }
        // Post-init: the drain loop runs post-init, so route targets QueueStore.
        markSessionInitialized()

        // Stage a profile property so the buffer is non-empty before the drain.
        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Bootstrap"))

        // Drive the queue reachable via the environment.
        await klaviyoSwiftEnvironment.requestQueue.flushNow()

        // willDrain must have folded the staged property into a createProfile request and sent it.
        let first = sentRequests.value.first
        guard case let .createProfile(_, payload) = first?.endpoint else {
            return XCTFail(
                "expected a .createProfile request from the env queue's willDrain, "
                    + "got \(String(describing: first?.endpoint))"
            )
        }
        XCTAssertEqual(
            payload.data.attributes.firstName, "Bootstrap",
            "the staged firstName must be folded into the sent createProfile payload"
        )
    }
}
