//
//  PushLogStore.swift
//  KlaviyoSwift
//

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

    func record(source: PushLogEntry.Source, title: String, body: String, customData: [String: String]) {
        let entry = PushLogEntry(source: source, title: title, body: body, customData: customData)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            entries.insert(entry, at: 0)
            if entries.count > maxEntries {
                entries.removeLast(entries.count - maxEntries)
            }
            save()
        }
    }

    func clear() {
        entries = []
        save()
    }

    private func load() -> [PushLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PushLogEntry].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
