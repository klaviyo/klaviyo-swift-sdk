//
//  InMemoryEnvironment.swift
//  klaviyo-swift-sdk
//
//  Shared in-memory KlaviyoEnvironment builder for tests exercising real JSON round-trips.
//  Each instance owns its own backing store.
//

@testable import KlaviyoCore
import Foundation

final class InMemoryEnvironment {
    /// Guards `diskStore` and the three failure-injection vars. The `FileClient` closures
    /// built by ``makeEnvironment()`` run on whatever thread the SDK's stores and tasks
    /// touch the file client from, so all access goes through this lock. The lock is never
    /// held across a `throw` or a call-out: throwing paths snapshot their decision inside
    /// the lock and throw after it is released.
    private let lock = NSLock()
    private var diskStore: [String: Data] = [:]
    private let libraryRoot: URL
    private let appSupportRoot: URL

    /// Fails every write matching this suffix until cleared. Not single-shot: IdentityStore's
    /// throwaway auto-mint persist on first hydrate would otherwise consume a single-shot flag
    /// before the write under test runs.
    var failWriteForPathSuffix: String? {
        get { lock.withLock { _failWriteForPathSuffix } }
        set { lock.withLock { _failWriteForPathSuffix = newValue } }
    }

    private var _failWriteForPathSuffix: String?

    /// Fails writes matching this suffix a fixed number of times, then stops on its own —
    /// simulates a transient error that clears up within a bounded number of retries.
    var transientFailure: (suffix: String, remaining: Int)? {
        get { lock.withLock { _transientFailure } }
        set { lock.withLock { _transientFailure = newValue } }
    }

    private var _transientFailure: (suffix: String, remaining: Int)?

    /// Fails every `removeItem` matching this suffix. The path remains on disk.
    var failRemoveForPathSuffix: String? {
        get { lock.withLock { _failRemoveForPathSuffix } }
        set { lock.withLock { _failRemoveForPathSuffix = newValue } }
    }

    private var _failRemoveForPathSuffix: String?

    init(
        libraryRoot: URL = URL(fileURLWithPath: "/tmp/klaviyo-migration-tests/library"),
        appSupportRoot: URL? = nil
    ) {
        self.libraryRoot = libraryRoot
        self.appSupportRoot = appSupportRoot ?? libraryRoot
    }

    subscript(path: String) -> Data? {
        get { lock.withLock { diskStore[path] } }
        set { lock.withLock { diskStore[path] = newValue } }
    }

    func makeEnvironment() -> KlaviyoEnvironment {
        var result = KlaviyoEnvironment.test()
        result.fileClient = FileClient(
            write: { [weak self] data, fileURL in try self?.write(data, to: fileURL) },
            fileExists: { [weak self] path in self?.fileExists(at: path) ?? false },
            removeItem: { [weak self] path in try self?.removeItem(at: path) },
            libraryDirectory: { [weak self] in self?.libraryRoot ?? URL(fileURLWithPath: "/tmp") },
            applicationSupportDirectory: { [weak self] in
                self?.appSupportRoot ?? URL(fileURLWithPath: "/tmp")
            }
        )
        result.encodeJSON = { try JSONEncoder().encode($0) }
        result.decoder = DataDecoder(jsonDecoder: JSONDecoder())
        result.dataFromUrl = { [weak self] fileURL in
            guard let self else { throw Self.noSuchFile(fileURL) }
            return try lock.withLock {
                guard let data = self.diskStore[fileURL.path] else { throw Self.noSuchFile(fileURL) }
                return data
            }
        }
        return result
    }

    // MARK: - FileClient operations (all state access under `lock`; throws after release)

    private enum WriteOutcome { case written, transientFailure, simulatedFailure }

    private func write(_ data: Data, to fileURL: URL) throws {
        let outcome: WriteOutcome = lock.withLock {
            if var transient = self._transientFailure, fileURL.path.hasSuffix(transient.suffix) {
                transient.remaining -= 1
                self._transientFailure = transient.remaining > 0 ? transient : nil
                return .transientFailure
            }
            if let suffix = self._failWriteForPathSuffix, fileURL.path.hasSuffix(suffix) {
                return .simulatedFailure
            }
            self.diskStore[fileURL.path] = data
            return .written
        }
        switch outcome {
        case .written:
            return
        case .transientFailure:
            throw NSError(domain: "InMemoryEnvironment", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "transient write failure for \(fileURL.lastPathComponent)"
            ])
        case .simulatedFailure:
            throw NSError(domain: "InMemoryEnvironment", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "simulated write failure for \(fileURL.lastPathComponent)"
            ])
        }
    }

    private func fileExists(at path: String) -> Bool {
        lock.withLock { self.diskStore[path] != nil }
    }

    private func removeItem(at path: String) throws {
        let shouldFail: Bool = lock.withLock {
            if let suffix = self._failRemoveForPathSuffix, path.hasSuffix(suffix) {
                return true
            }
            self.diskStore.removeValue(forKey: path)
            return false
        }
        if shouldFail {
            throw NSError(domain: "InMemoryEnvironment", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "simulated remove failure for \(path)"
            ])
        }
    }

    private static func noSuchFile(_ fileURL: URL) -> NSError {
        NSError(domain: "InMemoryEnvironment", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "no such file: \(fileURL.path)"
        ])
    }
}
