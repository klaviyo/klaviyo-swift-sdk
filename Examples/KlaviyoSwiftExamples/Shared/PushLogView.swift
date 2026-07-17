//
// PushLogView.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import SwiftUI

/// Displays a table (`List`) of push notifications the example app has received or handled —
/// the title, body, and any custom key-value pairs — matching the data extracted in
/// `AppDelegate`'s `UNUserNotificationCenterDelegate` and background-push handling.
struct PushLogView: View {
    @ObservedObject private var store = PushLogStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.entries) { entry in
                            PushLogRow(entry: entry)
                        }
                    }
                }
            }
            .navigationTitle("Push Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear", role: .destructive) { store.clear() }
                        .disabled(store.entries.isEmpty)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Push Notifications Yet")
                .font(.headline)
            Text("Received pushes will appear here with their title, body, and custom data.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PushLogRow: View {
    let entry: PushLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.source.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())

                Spacer()

                Text(entry.receivedAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(entry.title.isEmpty ? "(no title)" : entry.title)
                .font(.headline)

            Text(entry.body.isEmpty ? "(no body)" : entry.body)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !entry.customData.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.customData.sorted(by: { $0.key < $1.key }), id: \.key) { customKey, value in
                        Text("\(customKey): \(value)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
