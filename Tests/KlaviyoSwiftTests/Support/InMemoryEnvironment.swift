//
//  InMemoryEnvironment.swift
//  klaviyo-swift-sdk
//
//  Shared in-memory KlaviyoEnvironment builder for tests exercising real JSON round-trips —
//  the shared KlaviyoEnvironment.test() decoder force-substitutes any KlaviyoState decode with a
//  canned fixture, which this bypasses. Each instance owns its own backing store.
//

@testable import KlaviyoCore
import Foundation

final class InMemoryEnvironment {
    private var diskStore: [String: Data] = [:]
    private let libraryRoot: URL
    private let appSupportRoot: URL

    /// Fails every write matching this suffix until cleared. Not single-shot: IdentityStore's
    /// throwaway auto-mint persist on first hydrate would otherwise consume a single-shot flag
    /// before the write under test runs.
    var failWriteForPathSuffix: String?

    /// Fails writes matching this suffix a fixed number of times, then stops on its own —
    /// simulates a transient error that clears up within a bounded number of retries.
    var transientFailure: (suffix: String, remaining: Int)?

    /// Fails every `removeItem` matching this suffix. The path remains on disk.
    var failRemoveForPathSuffix: String?

    init(
        libraryRoot: URL = URL(fileURLWithPath: "/tmp/klaviyo-migration-tests/library"),
        appSupportRoot: URL? = nil
    ) {
        self.libraryRoot = libraryRoot
        self.appSupportRoot = appSupportRoot ?? libraryRoot
    }

    subscript(path: String) -> Data? {
        get { diskStore[path] }
        set { diskStore[path] = newValue }
    }

    func makeEnvironment() -> KlaviyoEnvironment {
        var result = KlaviyoEnvironment.test()
        result.fileClient = FileClient(
            write: { [weak self] data, fileURL in
                guard let self else { return }
                if var transient = self.transientFailure, fileURL.path.hasSuffix(transient.suffix) {
                    transient.remaining -= 1
                    self.transientFailure = transient.remaining > 0 ? transient : nil
                    throw NSError(domain: "InMemoryEnvironment", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "transient write failure for \(fileURL.lastPathComponent)"
                    ])
                }
                if let suffix = self.failWriteForPathSuffix, fileURL.path.hasSuffix(suffix) {
                    throw NSError(domain: "InMemoryEnvironment", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "simulated write failure for \(fileURL.lastPathComponent)"
                    ])
                }
                self.diskStore[fileURL.path] = data
            },
            fileExists: { [weak self] path in self?.diskStore[path] != nil },
            removeItem: { [weak self] path in
                guard let self else { return }
                if let suffix = self.failRemoveForPathSuffix, path.hasSuffix(suffix) {
                    throw NSError(domain: "InMemoryEnvironment", code: 4, userInfo: [
                        NSLocalizedDescriptionKey: "simulated remove failure for \(path)"
                    ])
                }
                self.diskStore.removeValue(forKey: path)
            },
            libraryDirectory: { [weak self] in self?.libraryRoot ?? URL(fileURLWithPath: "/tmp") },
            applicationSupportDirectory: { [weak self] in
                self?.appSupportRoot ?? URL(fileURLWithPath: "/tmp")
            }
        )
        result.encodeJSON = { try JSONEncoder().encode($0) }
        result.decoder = DataDecoder(jsonDecoder: JSONDecoder())
        result.dataFromUrl = { [weak self] fileURL in
            guard let data = self?.diskStore[fileURL.path] else {
                throw NSError(domain: "InMemoryEnvironment", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "no such file: \(fileURL.path)"
                ])
            }
            return data
        }
        return result
    }
}
