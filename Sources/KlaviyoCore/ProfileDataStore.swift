//
//  ProfileDataStore.swift
//  KlaviyoCore
//
//  Created by Ajay Subramanya on 11/30/25.
//

import Foundation

/// Persistent storage for user profile identity data.
///
/// This store provides a lightweight, persisted snapshot of profile information
/// that can be accessed by feature modules (like KlaviyoLocation) without
/// depending on the full SDK state management system.
///
/// The profile data is automatically saved by KlaviyoSwift whenever the SDK
/// state changes (debounced to prevent excessive I/O).
///
/// ## Usage
/// ```swift
/// // Save profile (typically called by KlaviyoSwift)
/// let profile = ProfileDataStore(
///     apiKey: "abc123",
///     anonymousId: "user-uuid",
///     email: "user@example.com"
/// )
/// ProfileDataStore.save(profile)
///
/// // Load profile (typically called by feature modules)
/// if let profile = ProfileDataStore.load(apiKey: "abc123") {
///     // Use profile data
/// }
/// ```
public struct ProfileDataStore: Codable, Equatable {
    /// The API key (company ID) for the Klaviyo account
    public var apiKey: String?

    /// Anonymous identifier for the user
    public var anonymousId: String?

    /// User's email address
    public var email: String?

    /// User's phone number
    public var phoneNumber: String?

    /// External identifier from the host application
    public var externalId: String?

    public init(
        apiKey: String? = nil,
        anonymousId: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil
    ) {
        self.apiKey = apiKey
        self.anonymousId = anonymousId
        self.email = email
        self.phoneNumber = phoneNumber
        self.externalId = externalId
    }
}

// MARK: - Persistence

extension ProfileDataStore {
    /// Saves the profile data to disk.
    ///
    /// The profile is saved to a JSON file in the Library directory,
    /// named using the API key to support multiple accounts.
    ///
    /// - Parameter profile: The profile data to save
    public static func save(_ profile: ProfileDataStore) {
        guard let apiKey = profile.apiKey else {
            environment.logger.error("Attempt to save profile without an API key.")
            return
        }

        let file = profileFile(apiKey: apiKey)

        do {
            let data = try environment.encodeJSON(AnyEncodable(profile))
            try environment.fileClient.write(data, file)
        } catch {
            environment.logger.error("Unable to save profile data: \(error.localizedDescription)")
        }
    }

    /// Loads the profile data from disk for a given API key.
    ///
    /// - Parameter apiKey: The API key to load profile data for
    /// - Returns: The profile data if found and valid, nil otherwise
    public static func load(apiKey: String) -> ProfileDataStore? {
        let file = profileFile(apiKey: apiKey)

        // Check if file exists
        guard environment.fileClient.fileExists(file.path) else {
            return nil
        }

        // Read file data
        guard let data = try? environment.dataFromUrl(file) else {
            environment.logger.error("Profile data file exists but is unreadable.")
            return nil
        }

        // Decode profile
        guard let profile: ProfileDataStore = try? environment.decoder.decode(data) else {
            environment.logger.error("Unable to decode profile data. File may be corrupted.")
            // Remove corrupted file
            try? environment.fileClient.removeItem(file.path)
            return nil
        }

        return profile
    }

    /// Convenience method to load profile using the apiKey from UserDefaults
    ///
    /// This is useful when the API key is not immediately available
    /// but has been stored from a previous session.
    ///
    /// - Returns: The profile data if API key exists and profile is found
    public static func loadCurrent() -> ProfileDataStore? {
        // Try to load from shared UserDefaults
        let defaults = UserDefaults.standard
        guard let apiKey = defaults.string(forKey: "com.klaviyo.current_api_key") else {
            return nil
        }
        return load(apiKey: apiKey)
    }

    /// Removes the profile file from disk.
    ///
    /// This should be called when the user logs out or the SDK is reset.
    ///
    /// - Parameter apiKey: The API key whose profile should be removed
    public static func remove(apiKey: String) {
        let file = profileFile(apiKey: apiKey)
        try? environment.fileClient.removeItem(file.path)
    }

    // MARK: - Private Helpers

    private static func profileFile(apiKey: String) -> URL {
        let fileName = "klaviyo-\(apiKey)-profile.json"
        let directory = environment.fileClient.libraryDirectory()
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}

// MARK: - Convenience Methods

extension ProfileDataStore {
    /// Returns true if the profile has a valid API key
    public var hasAPIKey: Bool {
        return apiKey != nil && !(apiKey?.isEmpty ?? true)
    }

    /// Returns true if the profile has at least one identifier (email, phone, or external ID)
    public var hasIdentifier: Bool {
        return (email != nil && !email!.isEmpty) ||
               (phoneNumber != nil && !phoneNumber!.isEmpty) ||
               (externalId != nil && !externalId!.isEmpty)
    }

    /// Returns true if the profile is complete enough to send events
    public var isValid: Bool {
        return hasAPIKey && anonymousId != nil
    }
}
