//
//  ProfileDataStoreTests.swift
//  KlaviyoCoreTests
//
//  Created by Claude Code on 11/28/24.
//

import XCTest
@testable import KlaviyoCore

class ProfileDataStoreTests: XCTestCase {
    let testAPIKey = "test-api-key-12345"

    override func setUp() {
        super.setUp()
        // Clean up any existing test data
        ProfileDataStore.remove(apiKey: testAPIKey)
    }

    override func tearDown() {
        // Clean up test data
        ProfileDataStore.remove(apiKey: testAPIKey)
        super.tearDown()
    }

    // MARK: - Basic Save/Load Tests

    func testSaveAndLoadProfile() {
        // Given: A profile with all fields populated
        let profile = ProfileDataStore(
            apiKey: testAPIKey,
            anonymousId: "anon-123",
            email: "test@example.com",
            phoneNumber: "+1234567890",
            externalId: "ext-456"
        )

        // When: Saving and loading the profile
        ProfileDataStore.save(profile)
        let loadedProfile = ProfileDataStore.load(apiKey: testAPIKey)

        // Then: The loaded profile should match
        XCTAssertNotNil(loadedProfile)
        XCTAssertEqual(loadedProfile?.apiKey, testAPIKey)
        XCTAssertEqual(loadedProfile?.anonymousId, "anon-123")
        XCTAssertEqual(loadedProfile?.email, "test@example.com")
        XCTAssertEqual(loadedProfile?.phoneNumber, "+1234567890")
        XCTAssertEqual(loadedProfile?.externalId, "ext-456")
    }

    func testSaveProfileWithPartialData() {
        // Given: A profile with only some fields populated
        let profile = ProfileDataStore(
            apiKey: testAPIKey,
            anonymousId: "anon-789",
            email: nil,
            phoneNumber: nil,
            externalId: nil
        )

        // When: Saving and loading the profile
        ProfileDataStore.save(profile)
        let loadedProfile = ProfileDataStore.load(apiKey: testAPIKey)

        // Then: Only populated fields should be present
        XCTAssertNotNil(loadedProfile)
        XCTAssertEqual(loadedProfile?.apiKey, testAPIKey)
        XCTAssertEqual(loadedProfile?.anonymousId, "anon-789")
        XCTAssertNil(loadedProfile?.email)
        XCTAssertNil(loadedProfile?.phoneNumber)
        XCTAssertNil(loadedProfile?.externalId)
    }

    func testLoadNonExistentProfile() {
        // When: Loading a profile that doesn't exist
        let loadedProfile = ProfileDataStore.load(apiKey: "non-existent-key")

        // Then: Should return nil
        XCTAssertNil(loadedProfile)
    }

    func testSaveWithoutAPIKey() {
        // Given: A profile without an API key
        let profile = ProfileDataStore(
            apiKey: nil,
            anonymousId: "anon-123",
            email: "test@example.com"
        )

        // When: Attempting to save
        ProfileDataStore.save(profile)

        // Then: Nothing should be saved (can't verify directly, but shouldn't crash)
        // This test mainly ensures the guard clause works correctly
    }

    // MARK: - Update Tests

    func testUpdateExistingProfile() {
        // Given: An existing profile
        let initialProfile = ProfileDataStore(
            apiKey: testAPIKey,
            anonymousId: "anon-123",
            email: "old@example.com",
            phoneNumber: nil,
            externalId: nil
        )
        ProfileDataStore.save(initialProfile)

        // When: Updating the profile with new data
        let updatedProfile = ProfileDataStore(
            apiKey: testAPIKey,
            anonymousId: "anon-123",
            email: "new@example.com",
            phoneNumber: "+9876543210",
            externalId: "ext-789"
        )
        ProfileDataStore.save(updatedProfile)

        // Then: The loaded profile should have updated data
        let loadedProfile = ProfileDataStore.load(apiKey: testAPIKey)
        XCTAssertNotNil(loadedProfile)
        XCTAssertEqual(loadedProfile?.email, "new@example.com")
        XCTAssertEqual(loadedProfile?.phoneNumber, "+9876543210")
        XCTAssertEqual(loadedProfile?.externalId, "ext-789")
    }

    // MARK: - Multiple Profiles Tests

    func testSaveMultipleProfiles() {
        // Given: Multiple profiles with different API keys
        let profile1 = ProfileDataStore(
            apiKey: "key-1",
            anonymousId: "anon-1",
            email: "user1@example.com"
        )
        let profile2 = ProfileDataStore(
            apiKey: "key-2",
            anonymousId: "anon-2",
            email: "user2@example.com"
        )

        // When: Saving both profiles
        ProfileDataStore.save(profile1)
        ProfileDataStore.save(profile2)

        // Then: Both should be loadable independently
        let loaded1 = ProfileDataStore.load(apiKey: "key-1")
        let loaded2 = ProfileDataStore.load(apiKey: "key-2")

        XCTAssertEqual(loaded1?.email, "user1@example.com")
        XCTAssertEqual(loaded2?.email, "user2@example.com")

        // Cleanup
        ProfileDataStore.remove(apiKey: "key-1")
        ProfileDataStore.remove(apiKey: "key-2")
    }

    // MARK: - Remove Tests

    func testRemoveProfile() {
        // Given: An existing profile
        let profile = ProfileDataStore(
            apiKey: testAPIKey,
            anonymousId: "anon-123",
            email: "test@example.com"
        )
        ProfileDataStore.save(profile)

        // When: Removing the profile
        ProfileDataStore.remove(apiKey: testAPIKey)

        // Then: The profile should no longer be loadable
        let loadedProfile = ProfileDataStore.load(apiKey: testAPIKey)
        XCTAssertNil(loadedProfile)
    }

    func testRemoveNonExistentProfile() {
        // When: Removing a profile that doesn't exist
        // Then: Should not crash
        XCTAssertNoThrow(ProfileDataStore.remove(apiKey: "non-existent-key"))
    }

    // MARK: - Convenience Methods Tests

    func testHasAPIKey() {
        // Given: Profiles with and without API keys
        let withKey = ProfileDataStore(apiKey: "key-123")
        let withoutKey = ProfileDataStore(apiKey: nil)
        let emptyKey = ProfileDataStore(apiKey: "")

        // Then: hasAPIKey should return correct values
        XCTAssertTrue(withKey.hasAPIKey)
        XCTAssertFalse(withoutKey.hasAPIKey)
        XCTAssertFalse(emptyKey.hasAPIKey)
    }

    func testHasIdentifier() {
        // Given: Profiles with different identifiers
        let withEmail = ProfileDataStore(email: "test@example.com")
        let withPhone = ProfileDataStore(phoneNumber: "+1234567890")
        let withExternal = ProfileDataStore(externalId: "ext-123")
        let withNone = ProfileDataStore()
        let withEmpty = ProfileDataStore(email: "")

        // Then: hasIdentifier should return correct values
        XCTAssertTrue(withEmail.hasIdentifier)
        XCTAssertTrue(withPhone.hasIdentifier)
        XCTAssertTrue(withExternal.hasIdentifier)
        XCTAssertFalse(withNone.hasIdentifier)
        XCTAssertFalse(withEmpty.hasIdentifier)
    }

    func testIsValid() {
        // Given: Profiles with different completeness
        let valid = ProfileDataStore(
            apiKey: "key-123",
            anonymousId: "anon-456"
        )
        let missingAPIKey = ProfileDataStore(
            apiKey: nil,
            anonymousId: "anon-456"
        )
        let missingAnonymousId = ProfileDataStore(
            apiKey: "key-123",
            anonymousId: nil
        )
        let bothMissing = ProfileDataStore()

        // Then: isValid should return correct values
        XCTAssertTrue(valid.isValid)
        XCTAssertFalse(missingAPIKey.isValid)
        XCTAssertFalse(missingAnonymousId.isValid)
        XCTAssertFalse(bothMissing.isValid)
    }

    // MARK: - Codable Tests

    func testCodableEncodeDecode() {
        // Given: A profile
        let original = ProfileDataStore(
            apiKey: testAPIKey,
            anonymousId: "anon-123",
            email: "test@example.com",
            phoneNumber: "+1234567890",
            externalId: "ext-456"
        )

        // When: Encoding and decoding
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        guard let data = try? encoder.encode(original),
              let decoded = try? decoder.decode(ProfileDataStore.self, from: data) else {
            XCTFail("Failed to encode/decode profile")
            return
        }

        // Then: Decoded profile should match original
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.apiKey, original.apiKey)
        XCTAssertEqual(decoded.anonymousId, original.anonymousId)
        XCTAssertEqual(decoded.email, original.email)
        XCTAssertEqual(decoded.phoneNumber, original.phoneNumber)
        XCTAssertEqual(decoded.externalId, original.externalId)
    }

    // MARK: - Equatable Tests

    func testEquality() {
        // Given: Two identical profiles
        let profile1 = ProfileDataStore(
            apiKey: "key-123",
            anonymousId: "anon-456",
            email: "test@example.com"
        )
        let profile2 = ProfileDataStore(
            apiKey: "key-123",
            anonymousId: "anon-456",
            email: "test@example.com"
        )

        // Then: They should be equal
        XCTAssertEqual(profile1, profile2)
    }

    func testInequality() {
        // Given: Two different profiles
        let profile1 = ProfileDataStore(
            apiKey: "key-123",
            anonymousId: "anon-456",
            email: "test1@example.com"
        )
        let profile2 = ProfileDataStore(
            apiKey: "key-123",
            anonymousId: "anon-456",
            email: "test2@example.com"
        )

        // Then: They should not be equal
        XCTAssertNotEqual(profile1, profile2)
    }

    // MARK: - Persistence Edge Cases

    func testRapidSaveLoad() {
        // Given: Multiple rapid save operations
        for i in 0..<10 {
            let profile = ProfileDataStore(
                apiKey: testAPIKey,
                anonymousId: "anon-\(i)",
                email: "test\(i)@example.com"
            )
            ProfileDataStore.save(profile)
        }

        // When: Loading the profile
        let loadedProfile = ProfileDataStore.load(apiKey: testAPIKey)

        // Then: Should have the last saved value
        XCTAssertNotNil(loadedProfile)
        XCTAssertEqual(loadedProfile?.anonymousId, "anon-9")
        XCTAssertEqual(loadedProfile?.email, "test9@example.com")
    }

    func testSpecialCharactersInData() {
        // Given: A profile with special characters
        let profile = ProfileDataStore(
            apiKey: testAPIKey,
            anonymousId: "anon-!@#$%^&*()",
            email: "test+alias@example.com",
            phoneNumber: "+1 (234) 567-8900",
            externalId: "ext-🎉"
        )

        // When: Saving and loading
        ProfileDataStore.save(profile)
        let loadedProfile = ProfileDataStore.load(apiKey: testAPIKey)

        // Then: Special characters should be preserved
        XCTAssertEqual(loadedProfile?.anonymousId, "anon-!@#$%^&*()")
        XCTAssertEqual(loadedProfile?.email, "test+alias@example.com")
        XCTAssertEqual(loadedProfile?.phoneNumber, "+1 (234) 567-8900")
        XCTAssertEqual(loadedProfile?.externalId, "ext-🎉")
    }
}
