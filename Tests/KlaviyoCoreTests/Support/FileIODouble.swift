// Tests/KlaviyoCoreTests/Support/FileIODouble.swift
//
// An in-memory KlaviyoEnvironment that round-trips real JSON so that
// Tasks 3 & 4 (SDKConfigStore / IdentityStore persistence) can share
// the same fixture.  Start from KlaviyoEnvironment.test() and override
// only the persistence-relevant closures.
//
@testable import KlaviyoCore
import Foundation

enum FileIODouble {
    // MARK: - Storage

    private static var store: [String: Data] = [:]

    private static let libraryRoot = URL(fileURLWithPath: "/tmp/klaviyo-tests")

    // MARK: - Encoder / decoder (real JSON round-trip)

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Factory

    /// Returns a fresh KlaviyoEnvironment backed by the shared in-memory dict.
    static func make() -> KlaviyoEnvironment {
        var result = KlaviyoEnvironment.test()

        result.fileClient = FileClient(
            write: { data, fileURL in
                store[fileURL.path] = data
            },
            fileExists: { path in
                store[path] != nil
            },
            removeItem: { path in
                store.removeValue(forKey: path)
            },
            libraryDirectory: { libraryRoot }
        )

        result.encodeJSON = { encodable in
            try jsonEncoder.encode(encodable)
        }

        result.decoder = DataDecoder(jsonDecoder: jsonDecoder)

        result.dataFromUrl = { fileURL in
            guard let data = store[fileURL.path] else {
                throw CocoaError(.fileNoSuchFile)
            }
            return data
        }

        return result
    }

    // MARK: - Teardown

    /// Clears the shared in-memory file store between tests.
    static func reset() {
        store.removeAll()
    }
}
