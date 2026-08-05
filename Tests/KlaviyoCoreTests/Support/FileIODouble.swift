// Tests/KlaviyoCoreTests/Support/FileIODouble.swift
//
// An in-memory KlaviyoEnvironment that round-trips real JSON so that
// Tasks 3 & 4 (SDKConfigStore / IdentityStore persistence) can share
// the same fixture.  Start from KlaviyoEnvironment.test() and override
// only the persistence-relevant closures.
//
// Each instance owns its own byte store — test classes hold an instance
// property, eliminating static-state cross-test-class contamination.
//
@testable import KlaviyoCore
import Foundation

final class FileIODouble {
    // MARK: - Storage (instance-scoped)

    private var store: [String: Data] = [:]

    private let libraryRoot = URL(fileURLWithPath: "/tmp/klaviyo-tests")

    // MARK: - Encoder / decoder (real JSON round-trip)

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Factory

    /// Returns a KlaviyoEnvironment whose file I/O and JSON codecs are backed
    /// by this instance's in-memory byte store (real round-trip, not the
    /// no-op TestUtils stubs). Closures capture `self`, so each test object
    /// gets isolated state.
    func makeEnvironment() -> KlaviyoEnvironment {
        var result = KlaviyoEnvironment.test()

        result.fileClient = FileClient(
            write: { [weak self] data, fileURL in
                self?.store[fileURL.path] = data
            },
            fileExists: { [weak self] path in
                self?.store[path] != nil
            },
            removeItem: { [weak self] path in
                self?.store.removeValue(forKey: path)
            },
            libraryDirectory: { [weak self] in
                self?.libraryRoot ?? URL(fileURLWithPath: "/tmp/klaviyo-tests")
            }
        )

        result.encodeJSON = { [weak self] encodable in
            guard let self else { throw CocoaError(.fileNoSuchFile) }
            return try self.jsonEncoder.encode(encodable)
        }

        result.decoder = DataDecoder(jsonDecoder: jsonDecoder)

        result.dataFromUrl = { [weak self] fileURL in
            guard let data = self?.store[fileURL.path] else {
                throw CocoaError(.fileNoSuchFile)
            }
            return data
        }

        return result
    }
}
