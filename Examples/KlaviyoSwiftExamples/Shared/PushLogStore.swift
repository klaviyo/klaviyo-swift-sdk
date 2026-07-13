//
//  PushLogStore.swift
//  KlaviyoSwift
//

import Combine
import Foundation

/// Keeps a lightly-persisted history of push notifications received by the app so the Push Log
/// screen can display each notification's title, body, and custom data without needing to
/// reproduce the push or dig through the Xcode console.
final class PushLogStore: ObservableObject {
    static let shared = PushLogStore()

    @Published private(set) var entries: [PushLogEntry] = []

    private let storageKey = "com.klaviyo.example.pushLog"
    private let maxEntries = 50

    private init() {
        entries = load()
    }

    /// `completion` fires only after the entry has been appended and saved — callers that need to
    /// guarantee persistence before finishing background work (e.g. before calling APNs'
    /// `completionHandler`) should wait for it rather than assuming this returns synchronously.
    func record(
        source: PushLogEntry.Source,
        title: String,
        body: String,
        customData: [String: String],
        completion: (() -> Void)? = nil
    ) {
        let entry = PushLogEntry(source: source, title: title, body: body, customData: customData)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            entries.insert(entry, at: 0)
            if entries.count > maxEntries {
                entries.removeLast(entries.count - maxEntries)
            }
            save()
            completion?()
        }
    }

    func clear() {
        // Dispatch through the same queue as `record` so a clear can't race a push that's
        // already mid-flight — whichever was invoked first is guaranteed to run first.
        DispatchQueue.main.async { [weak self] in
            self?.entries = []
            self?.save()
        }
    }

    private func load() -> [PushLogEntry] {
        // Push payloads can carry sensitive custom data (promo codes, identifiers, etc.) — only
        // persist across launches in Debug builds. Release builds keep this in-memory only for
        // the current session.
        #if DEBUG
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PushLogEntry].self, from: data)
        else {
            return []
        }
        return decoded
        #else
        return []
        #endif
    }

    private func save() {
        #if DEBUG
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        #endif
    }
}
