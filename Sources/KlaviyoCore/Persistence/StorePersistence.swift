//
//  StorePersistence.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

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
    public static let unattributed = "klaviyo-unattributed.json"
}

// MARK: - Load / save helpers

/// Resolves the on-disk URL for a store file, under the canonical `applicationSupportDirectory()`
/// home. No caller may opt into any other location — every canonical store's file lives here.
func storeFileURL(_ fileName: String) -> URL {
    environment.fileClient.applicationSupportDirectory()
        .appendingPathComponent(fileName, isDirectory: false)
}

/// Loads a decodable value from the named file. Returns `nil` if the file is absent or cannot be
/// decoded; an undecodable file is removed to avoid repeated failures.
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

/// Removes the named file if it exists. Logs on failure; never throws to the caller.
func removePersisted(fileName: String) {
    let fileURL = storeFileURL(fileName)
    guard environment.fileClient.fileExists(fileURL.path) else { return }
    do {
        try environment.fileClient.removeItem(fileURL.path)
    } catch {
        environment.logger.error("Unable to remove \(fileName).")
    }
}

/// Persists an encodable value to the named file. Logs on failure; never throws to the caller.
public func savePersisted(_ value: some Encodable, fileName: String) {
    do {
        let data = try environment.encodeJSON(value)
        try environment.fileClient.write(data, storeFileURL(fileName))
    } catch {
        environment.logger.error("Unable to persist \(fileName).")
    }
}
