//
//  LogStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/19/25.
//

import Combine
import Foundation
import KlaviyoCore
import OSLog

@available(iOS 15.0, *)
@MainActor @objc
public final class LogStore: NSObject, ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: LogStore.self)
    )

    @Published public private(set) var entries: [String] = []

    @objc
    override public init() {
        super.init()
        setupLifecycleObserver()
    }

    private var lifecycleCancellable: AnyCancellable?

    private var logFileURL: URL? {
        guard let docFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let loggerFolder = docFolder.appendingPathComponent("Logger", isDirectory: true)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date.now)
        let fileName = "Logs-\(dateString).txt"
        return loggerFolder.appendingPathComponent(fileName)
    }

    deinit {
        lifecycleCancellable?.cancel()
    }

    private func setupLifecycleObserver() {
        // Only set up if not already observing
        guard lifecycleCancellable == nil else { return }

        // Observe app lifecycle to automatically export logs
        lifecycleCancellable = environment.appLifeCycle.lifeCycleEvents()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .backgrounded, .terminated:
                    self.export()
                default:
                    break
                }
            }
    }

    public func export() {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let date = Date.now.addingTimeInterval(-24 * 3600)
            let position = store.position(date: date)
            let mainBundleId = Bundle.main.bundleIdentifier ?? ""
            let klaviyoSDKPrefix = "com.klaviyo.klaviyo-swift-sdk."

            entries = try store
                .getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { entry in
                    entry.subsystem.hasPrefix(klaviyoSDKPrefix) || entry.subsystem == mainBundleId
                }
                .map { "[\($0.date.formatted(date: .omitted, time: .shortened))] [\($0.category)] \($0.composedMessage)" }

            // Write entries to file
            writeLogsToFile(entries)
        } catch {
            Self.logger.warning("\(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeLogsToFile(_ logEntries: [String]) {
        guard let fileURL = logFileURL else {
            Self.logger.warning("Unable to get log file URL")
            return
        }

        let fileManager = FileManager.default
        let loggerFolder = fileURL.deletingLastPathComponent()

        do {
            // Create Logger folder if it doesn't exist
            try fileManager.createDirectory(at: loggerFolder, withIntermediateDirectories: true, attributes: nil)

            // Append logs to file
            let logText = logEntries.joined(separator: "\n") + "\n"
            if fileManager.fileExists(atPath: fileURL.path) {
                // Append to existing file
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    fileHandle.seekToEndOfFile()
                    if let data = logText.data(using: .utf8) {
                        fileHandle.write(data)
                        try? fileHandle.synchronize()
                    }
                    try? fileHandle.close()
                }
            } else {
                // Create new file
                try logText.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            Self.logger.warning("Failed to write logs to file: \(error.localizedDescription, privacy: .public)")
        }
    }
}
