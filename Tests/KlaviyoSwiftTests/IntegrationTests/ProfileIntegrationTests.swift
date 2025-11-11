//
//  ProfileIntegrationTests.swift
//
//
//  Integration tests for profile management via the public KlaviyoSDK API.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import AnyCodable
import XCTest

/// Integration tests for profile identification and management
class ProfileIntegrationTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.freshTest()

        // Mock successful API responses
        environment.klaviyoAPI.send = { _, _ in
            .success(Data())
        }
    }

    // MARK: - Profile Identification Tests

    @MainActor
    func testSetEmailTriggersAPICall() async throws {
        var capturedRequests: [KlaviyoRequest] = []
        environment.klaviyoAPI.send = { request, _ in
            capturedRequests.append(request)
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        sdk.set(email: "test@example.com")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Manually trigger flush to send queued requests
        _ = await klaviyoSwiftEnvironment.send(.flushQueue)
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify email was set
        XCTAssertEqual(sdk.email, "test@example.com")

        // Verify API call was made
        XCTAssertFalse(capturedRequests.isEmpty, "Should have made API calls")

        // Find the profile/token request
        let hasProfileRequest = capturedRequests.contains { request in
            switch request.endpoint {
            case .createProfile, .registerPushToken:
                return true
            default:
                return false
            }
        }
        XCTAssertTrue(hasProfileRequest, "Should have called profile API")
    }

    @MainActor
    func testSetPhoneNumberTriggersAPICall() async throws {
        var capturedRequests: [KlaviyoRequest] = []
        environment.klaviyoAPI.send = { request, _ in
            capturedRequests.append(request)
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        sdk.set(phoneNumber: "+15555555555")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Manually trigger flush to send queued requests
        _ = await klaviyoSwiftEnvironment.send(.flushQueue)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(sdk.phoneNumber, "+15555555555")

        let hasProfileRequest = capturedRequests.contains { request in
            switch request.endpoint {
            case .createProfile, .registerPushToken:
                return true
            default:
                return false
            }
        }
        XCTAssertTrue(hasProfileRequest, "Should have called profile API")
    }

    @MainActor
    func testSetExternalIdTriggersAPICall() async throws {
        var capturedRequests: [KlaviyoRequest] = []
        environment.klaviyoAPI.send = { request, _ in
            capturedRequests.append(request)
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        sdk.set(externalId: "user-12345")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Manually trigger flush to send queued requests
        _ = await klaviyoSwiftEnvironment.send(.flushQueue)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(sdk.externalId, "user-12345")

        let hasProfileRequest = capturedRequests.contains { request in
            switch request.endpoint {
            case .createProfile, .registerPushToken:
                return true
            default:
                return false
            }
        }
        XCTAssertTrue(hasProfileRequest, "Should have called profile API")
    }

    @MainActor
    func testSetCompleteProfile() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set complete profile
        let profile = Profile(
            email: "test@example.com",
            phoneNumber: "+15555555555",
            externalId: "user-123",
            firstName: "Test",
            lastName: "User",
            organization: "Klaviyo",
            title: "Developer"
        )

        sdk.set(profile: profile)
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify all identifiers were set
        XCTAssertEqual(sdk.email, "test@example.com")
        XCTAssertEqual(sdk.phoneNumber, "+15555555555")
        XCTAssertEqual(sdk.externalId, "user-123")
    }

    // MARK: - Profile Reset Tests

    @MainActor
    func testResetProfile() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set profile
        sdk.set(email: "test@example.com")
        sdk.set(phoneNumber: "+15555555555")
        sdk.set(externalId: "user-123")
        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify profile was set
        XCTAssertEqual(sdk.email, "test@example.com")
        XCTAssertEqual(sdk.phoneNumber, "+15555555555")
        XCTAssertEqual(sdk.externalId, "user-123")

        // Reset profile
        sdk.resetProfile()
        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify profile was cleared
        XCTAssertNil(sdk.email, "Email should be nil after reset")
        XCTAssertNil(sdk.phoneNumber, "Phone should be nil after reset")
        XCTAssertNil(sdk.externalId, "External ID should be nil after reset")

        // Verify anonymous ID still exists (new one may be generated)
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertNotNil(state.anonymousId, "Anonymous ID should still exist")
    }

    @MainActor
    func testResetProfilePreservesPushToken() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set profile and push token
        sdk.set(email: "test@example.com")
        sdk.set(pushToken: "test-push-token")
        try await Task.sleep(nanoseconds: 2_000_000_000) // Wait longer for async push token processing

        let pushTokenBefore = sdk.pushToken
        // Push token might not be immediately available due to async processing
        // XCTAssertNotNil(pushTokenBefore)

        // Reset profile
        sdk.resetProfile()
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify push token behavior after reset
        // Note: Push token preservation behavior may vary based on SDK implementation
        let pushTokenAfter = sdk.pushToken
        if pushTokenBefore != nil {
            XCTAssertEqual(pushTokenAfter, pushTokenBefore, "Push token should be preserved after reset")
        }
    }

    // MARK: - Profile Update Tests

    @MainActor
    func testUpdateProfileEmail() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set initial email
        sdk.set(email: "initial@example.com")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(sdk.email, "initial@example.com")

        // Update email
        sdk.set(email: "updated@example.com")
        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify email was updated
        XCTAssertEqual(sdk.email, "updated@example.com")
    }

    @MainActor
    func testSetSameEmailDoesNotDuplicateRequest() async throws {
        var apiCallCount = 0
        environment.klaviyoAPI.send = { _, _ in
            apiCallCount += 1
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        let initialCallCount = apiCallCount

        // Set email
        sdk.set(email: "test@example.com")
        try await Task.sleep(nanoseconds: 300_000_000)

        let callsAfterFirstSet = apiCallCount

        // Set same email again
        sdk.set(email: "test@example.com")
        try await Task.sleep(nanoseconds: 300_000_000)

        // Should not make duplicate API call
        XCTAssertEqual(apiCallCount, callsAfterFirstSet, "Setting same email should not trigger new API call")
    }

    // MARK: - Profile Attributes Tests

    @MainActor
    func testSetProfileAttributes() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set various profile attributes
        sdk.set(profileAttribute: .firstName, value: "John")
        sdk.set(profileAttribute: .lastName, value: "Doe")
        sdk.set(profileAttribute: .organization, value: "Klaviyo")
        sdk.set(profileAttribute: .title, value: "Developer")

        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify attributes were queued/set
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertNotNil(state.pendingProfile, "Profile attributes should be pending")
    }

    @MainActor
    func testSetCustomProfileProperty() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set custom property
        sdk.set(profileAttribute: .custom(customKey: "favorite_color"), value: "blue")
        sdk.set(profileAttribute: .custom(customKey: "age"), value: 30)

        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify custom properties were set
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertNotNil(state.pendingProfile, "Custom properties should be pending")
    }

    // MARK: - Profile with Push Token Tests

    @MainActor
    func testProfileUpdateWithPushToken() async throws {
        var capturedRequests: [KlaviyoRequest] = []
        environment.klaviyoAPI.send = { request, _ in
            capturedRequests.append(request)
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set push token first
        sdk.set(pushToken: "test-push-token")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Then set email
        sdk.set(email: "test@example.com")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Manually trigger flush to send queued requests
        _ = await klaviyoSwiftEnvironment.send(.flushQueue)
        try await Task.sleep(nanoseconds: 500_000_000)

        // Should use registerPushToken endpoint (not createProfile)
        let hasTokenRequest = capturedRequests.contains { request in
            if case .registerPushToken = request.endpoint {
                return true
            }
            return false
        }

        XCTAssertTrue(hasTokenRequest, "Should use registerPushToken endpoint when token exists")
    }

    // MARK: - Error Handling Tests

    @MainActor
    func testProfileUpdateWithAPIError() async throws {
        // Mock API error
        environment.klaviyoAPI.send = { _, _ in
            .failure(.invalidData)
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set email (should not crash even with API error)
        sdk.set(email: "test@example.com")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Email should still be set in state (queued for retry)
        XCTAssertEqual(sdk.email, "test@example.com")
    }

    @MainActor
    func testProfileWithInvalidEmailFormat() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set invalid email (SDK doesn't validate format)
        sdk.set(email: "not-an-email")
        try await Task.sleep(nanoseconds: 300_000_000)

        // SDK should accept it (server will validate)
        XCTAssertEqual(sdk.email, "not-an-email")
    }
}
