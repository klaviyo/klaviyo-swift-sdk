//
//  QueuePersistence.swift
//  KlaviyoCore
//
//  Created by Claude Code on 2025-11-10.
//

import Foundation

/// Persisted queue state
struct PersistedQueueState: Codable {
    /// Version identifier for persistence format
    let version: String
    /// API key associated with this queue
    let apiKey: String
    /// Immediate priority requests
    let immediate: [QueuedRequest]
    /// Normal priority requests
    let normal: [QueuedRequest]

    static let currentVersion = "2.0"
}

/// Handles persistence of queue state to disk
struct QueuePersistence {
    /// File client for disk operations
    let fileClient: FileClient
    /// API key for this queue
    let apiKey: String
    /// JSON encoder
    let encoder: (Encodable) throws -> Data
    /// JSON decoder
    let decoder: (Data) -> Decodable?

    init(
        fileClient: FileClient = environment.fileClient,
        apiKey: String,
        encoder: @escaping (Encodable) throws -> Data = { try environment.encoder.encode($0) },
        decoder: @escaping (Data) -> Decodable? = { try? environment.decoder.decode(PersistedQueueState.self, from: $0) }
    ) {
        self.fileClient = fileClient
        self.apiKey = apiKey
        self.encoder = encoder
        self.decoder = decoder
    }

    // MARK: - Public API

    /// Save queue state to disk
    /// - Parameters:
    ///   - immediate: Immediate priority requests
    ///   - normal: Normal priority requests
    /// - Throws: FileClient errors or encoding errors
    func save(immediate: [QueuedRequest], normal: [QueuedRequest]) throws {
        let state = PersistedQueueState(
            version: PersistedQueueState.currentVersion,
            apiKey: apiKey,
            immediate: immediate,
            normal: normal
        )

        let data = try encoder(state)
        let url = queueFilePath()

        try fileClient.write(data, url)
    }

    /// Load queue state from disk
    /// - Returns: Tuple of immediate and normal requests, or empty arrays if file doesn't exist or is invalid
    func load() -> (immediate: [QueuedRequest], normal: [QueuedRequest]) {
        let url = queueFilePath()

        // Check if file exists
        guard fileClient.fileExists(url.path) else {
            return (immediate: [], normal: [])
        }

        // Read file
        guard let data = try? environment.dataFromUrl(url) else {
            environment.logger.error("Failed to read queue file at \(url.path)")
            return (immediate: [], normal: [])
        }

        // Decode
        guard let state = decoder(data) as? PersistedQueueState else {
            environment.logger.error("Failed to decode queue state. Removing corrupt file.")
            try? fileClient.removeItem(url.path)
            return (immediate: [], normal: [])
        }

        // Validate API key matches
        guard state.apiKey == apiKey else {
            environment.logger.warning("Queue file API key mismatch. Expected '\(apiKey)', found '\(state.apiKey)'. Ignoring file.")
            return (immediate: [], normal: [])
        }

        // Validate version (for future migrations)
        if state.version != PersistedQueueState.currentVersion {
            environment.logger.warning("Queue file version mismatch. Expected '\(PersistedQueueState.currentVersion)', found '\(state.version)'. Attempting to load anyway.")
        }

        return (immediate: state.immediate, normal: state.normal)
    }

    /// Clear persisted queue file
    /// - Throws: FileClient errors
    func clear() throws {
        let url = queueFilePath()
        if fileClient.fileExists(url.path) {
            try fileClient.removeItem(url.path)
        }
    }

    /// Check if a persisted queue file exists
    func exists() -> Bool {
        fileClient.fileExists(queueFilePath().path)
    }

    // MARK: - Private Helpers

    /// Get the file path for the persisted queue
    private func queueFilePath() -> URL {
        let libraryDir = fileClient.libraryDirectory()
        return libraryDir.appendingPathComponent("klaviyo-\(apiKey)-queue-v2.json")
    }
}
