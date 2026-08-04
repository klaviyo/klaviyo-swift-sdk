// Sources/KlaviyoCore/Persistence/StorePersistence.swift
import Foundation

// MARK: - Versioned Persistence DTOs

public struct PersistedIdentity: Codable, Equatable {
    public static let currentVersion = 1
    public var version: Int
    public var profile: ProfileData
    public var pushToken: PushTokenData?

    public init(version: Int, profile: ProfileData, pushToken: PushTokenData? = nil) {
        self.version = version
        self.profile = profile
        self.pushToken = pushToken
    }
}

public struct PersistedConfig: Codable, Equatable {
    public static let currentVersion = 1
    public var version: Int
    public var apiKey: String?

    public init(version: Int, apiKey: String? = nil) {
        self.version = version
        self.apiKey = apiKey
    }
}

// MARK: - Well-known store file names

public enum StoreFile {
    public static let identity = "klaviyo-identity.json"
    public static let config = "klaviyo-config.json"
}

// MARK: - Load / save helpers

func storeFileURL(_ fileName: String) -> URL {
    environment.fileClient.libraryDirectory()
        .appendingPathComponent(fileName, isDirectory: false)
}

/// Loads a decodable value from the named file in the library directory.
/// Returns `nil` if the file is absent or cannot be decoded;
/// an undecodable file is removed to avoid repeated failures.
public func loadPersisted<T: Decodable>(_ type: T.Type, fileName: String) -> T? {
    let fileURL = storeFileURL(fileName)
    guard environment.fileClient.fileExists(fileURL.path) else { return nil }
    guard let data = try? environment.dataFromUrl(fileURL) else {
        environment.logger.error("Unable to read \(fileName); removing.")
        try? environment.fileClient.removeItem(fileURL.path)
        return nil
    }
    guard let value: T = try? environment.decoder.decode(data) else {
        environment.logger.error("Unable to decode \(fileName); removing.")
        try? environment.fileClient.removeItem(fileURL.path)
        return nil
    }
    return value
}

/// Persists an encodable value to the named file in the library directory.
/// Logs on failure; never throws to the caller.
public func savePersisted(_ value: some Encodable, fileName: String) {
    do {
        let data = try environment.encodeJSON(value)
        try environment.fileClient.write(data, storeFileURL(fileName))
    } catch {
        environment.logger.error("Unable to persist \(fileName).")
    }
}
