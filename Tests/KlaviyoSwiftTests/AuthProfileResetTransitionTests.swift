//
//  AuthProfileResetTransitionTests.swift
//  KlaviyoSwiftTests
//

@testable import KlaviyoSwift
import KlaviyoCore
import XCTest

@MainActor
final class AuthProfileResetTransitionTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        AuthTokenCommandQueue.shared.enqueue(.unregister)
        await AuthTokenCommandQueue.shared.waitForPendingCommands()
    }

    override func tearDown() async throws {
        AuthTokenCommandQueue.shared.enqueue(.unregister)
        await AuthTokenCommandQueue.shared.waitForPendingCommands()
    }

    func testCompanyFenceCoalescesResetAndLaterRegisterWaitsForProfile() async throws {
        let transition = AuthProfileResetTransition()
        let releaseDispatch = AuthTestGate()
        let resetDispatched = expectation(description: "reset dispatched after auth clear")
        let before = AuthTokenCommandQueue.shared.revision
        let reset = AuthTokenCommandQueue.shared.enqueue(.profileReset(transition) {
            resetDispatched.fulfill()
            await releaseDispatch.wait()
        })
        let companyFence = AuthTokenCommandQueue.shared.companyTransitionFence()

        XCTAssertEqual(AuthTokenCommandQueue.shared.revision, before + 1)
        await fulfillment(of: [resetDispatched], timeout: 2)
        let fenceCompleted = expectation(description: "company fence completed")
        Task {
            await companyFence.value
            fenceCompleted.fulfill()
        }
        await fulfillment(of: [fenceCompleted], timeout: 2)

        let token = try makeAuthJWT(subject: "new-user")
        AuthTokenCommandQueue.shared.enqueue(.register { token })
        do {
            _ = try await AuthTokenManager.shared.currentToken(mode: .background)
            XCTFail("Later registration ran before profile reset completed")
        } catch {
            XCTAssertEqual(error as? AuthTokenError, .noProviderRegistered)
        }

        await releaseDispatch.open()
        await transition.completeProfileReset()
        await reset.value
        await AuthTokenCommandQueue.shared.waitForPendingCommands()
        let registeredToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertEqual(registeredToken, token)
    }

    func testCompanyClearAheadOfResetRemainsASeparatePrefix() async {
        let before = AuthTokenCommandQueue.shared.revision
        let companyFence = AuthTokenCommandQueue.shared.companyTransitionFence()
        let transition = AuthProfileResetTransition()
        let reset = AuthTokenCommandQueue.shared.enqueue(.profileReset(transition) {})

        XCTAssertEqual(AuthTokenCommandQueue.shared.revision, before + 2)
        await companyFence.value
        let authCleared = expectation(description: "reset auth clear completed")
        Task {
            await transition.waitForAuthClear()
            authCleared.fulfill()
        }
        await fulfillment(of: [authCleared], timeout: 2)
        await transition.completeProfileReset()
        await reset.value
    }

    func testCompanyFenceCoversLatestPendingReset() async {
        let first = AuthProfileResetTransition()
        let second = AuthProfileResetTransition()
        let firstCommand = AuthTokenCommandQueue.shared.enqueue(.profileReset(first) {})
        let secondCommand = AuthTokenCommandQueue.shared.enqueue(.profileReset(second) {})
        let companyFence = AuthTokenCommandQueue.shared.companyTransitionFence()
        await first.waitForAuthClear()

        let completedEarly = expectation(description: "company fence completed early")
        completedEarly.isInverted = true
        let observer = Task {
            await companyFence.value
            completedEarly.fulfill()
        }
        await fulfillment(of: [completedEarly], timeout: 0.1)

        await first.completeProfileReset()
        await firstCommand.value
        await second.waitForAuthClear()
        let completed = expectation(description: "company fence completed")
        Task {
            await companyFence.value
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 2)
        await second.completeProfileReset()
        await secondCommand.value
        await observer.value
    }

    func testRetargetedCompanyCompletionReplaysReservedReset() async throws {
        var state = KlaviyoState(
            apiKey: "company-A",
            email: "a@example.com",
            anonymousId: "anonymous-A",
            queue: [],
            initalizationState: .initialized
        )
        let reducer = KlaviyoReducer()
        let transition = AuthProfileResetTransition()
        let reset = AuthTokenCommandQueue.shared.enqueue(.profileReset(transition) {})
        let beforeCompany = AuthTokenCommandQueue.shared.revision

        _ = reducer.reduce(into: &state, action: .initialize("company-B"))
        _ = reducer.reduce(into: &state, action: .resetProfileWithQueuedAuthClear(transition))
        _ = reducer.reduce(into: &state, action: .initialize("company-C"))
        XCTAssertEqual(AuthTokenCommandQueue.shared.revision, beforeCompany)
        await transition.waitForAuthClear()

        _ = reducer.reduce(into: &state, action: .completeCompanyChange("company-B"))
        XCTAssertEqual(state.initalizationState, .changingCompany("company-C"))
        _ = reducer.reduce(into: &state, action: .completeCompanyChange("company-C"))
        XCTAssertEqual(state.initalizationState, .resettingProfile)
        let active = try XCTUnwrap(state.activeProfileResetTransition)
        XCTAssertEqual(active, transition)
        _ = reducer.reduce(into: &state, action: .completeProfileReset)
        await transition.completeProfileReset()
        await reset.value

        XCTAssertEqual(state.apiKey, "company-C")
        XCTAssertNil(state.email)
    }

    func testCancelledCompanyChangeCompletesResetWithoutStaleUnregister() async {
        var state = KlaviyoState(
            apiKey: "company-A",
            email: "a@example.com",
            anonymousId: "anonymous-A",
            queue: [],
            initalizationState: .initialized
        )
        state.pushTokenData = KlaviyoState.PushTokenData(
            pushToken: "device-token",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: .init(context: environment.appContextInfo())
        )
        let reducer = KlaviyoReducer()
        let transition = AuthProfileResetTransition()
        let reset = AuthTokenCommandQueue.shared.enqueue(.profileReset(transition) {})
        await transition.waitForAuthClear()

        _ = reducer.reduce(into: &state, action: .resetProfileWithQueuedAuthClear(transition))
        _ = reducer.reduce(into: &state, action: .initialize("company-B"))
        XCTAssertNotNil(state.pendingCompanyUnregisterRequest)
        _ = reducer.reduce(into: &state, action: .initialize("company-A"))
        XCTAssertNil(state.pendingCompanyAPIKey)
        _ = reducer.reduce(into: &state, action: .completeProfileReset)
        await transition.completeProfileReset()
        await reset.value

        XCTAssertEqual(state.initalizationState, .initialized)
        XCTAssertEqual(state.apiKey, "company-A")
        XCTAssertNil(state.email)
        XCTAssertNil(state.pendingCompanyUnregisterRequest)
    }

    func testUninitializedReservedResetCompletesWithoutReducerTransition() async {
        let transition = AuthProfileResetTransition()
        let reset = AuthTokenCommandQueue.shared.enqueue(.profileReset(transition) {})
        await transition.waitForAuthClear()
        var state = KlaviyoState(queue: [], initalizationState: .uninitialized)

        _ = KlaviyoReducer().reduce(into: &state, action: .resetProfileWithQueuedAuthClear(transition))

        let completed = expectation(description: "reserved reset completed")
        Task {
            await reset.value
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(state.initalizationState, .uninitialized)
    }
}
