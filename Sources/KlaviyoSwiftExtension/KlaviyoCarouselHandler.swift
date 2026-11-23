//
//  KlaviyoCarouselHandler.swift
//

import Foundation
import OSLog
import UserNotifications

/// Downloads a carousel push's card images as attachments and sets the static carousel category.
///
/// One instance handles one notification. It finishes when every download completes, when the batch
/// deadline passes, or when ``finishNow()`` is called from `serviceExtensionTimeWillExpire`, whichever
/// comes first, and calls `completion` exactly once.
///
/// The carousel category has no actions. The content extension sets each notification's buttons
/// itself, because a shared category's actions would be overwritten by whichever carousel arrived last.
final class KlaviyoCarouselHandler {
    /// Attachment identifiers are `card-<position>`, so the content extension can match each
    /// attachment back to its card even when earlier cards failed to download.
    static let attachmentIdentifierPrefix = "card-"
    static let perRequestTimeout: TimeInterval = 8
    /// Well inside the ~30 seconds iOS gives a notification service extension.
    static let batchDeadline: TimeInterval = 20

    /// File extensions for the image types `UNNotificationAttachment` accepts, by MIME type.
    /// Attachments are typed by file extension, and card URLs often have none or a misleading one.
    /// `image/jpg` isn't a registered type, but some servers send it.
    static let imageFileExtensions = ["image/jpeg": "jpg", "image/jpg": "jpg", "image/png": "png", "image/gif": "gif"]
    private static let supportedPathExtensions: Set<String> = ["jpg", "jpeg", "png", "gif"]

    /// A downloaded file and the MIME type the server reported for it.
    struct DownloadedFile {
        let location: URL
        let mimeType: String?
    }

    /// Downloads `url` to a temporary file, calling back with it or nil on failure.
    /// The file is deleted when the callback returns.
    typealias Download = (_ url: URL, _ completion: @escaping (DownloadedFile?) -> Void) -> Void

    struct Dependencies {
        var download: Download
        var makeAttachment: (_ identifier: String, _ fileURL: URL) throws -> UNNotificationAttachment
        var registerCarouselCategory: () -> Void
        /// Cancels downloads still running once the carousel is delivered.
        var cancelDownloads: () -> Void

        static func live() -> Dependencies {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = perRequestTimeout
            configuration.timeoutIntervalForResource = perRequestTimeout
            let session = URLSession(configuration: configuration)
            return Dependencies(
                download: { url, completion in
                    session.downloadTask(with: url) { location, response, error in
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        guard error == nil, (200..<300).contains(status) else {
                            completion(nil)
                            return
                        }
                        completion(location.map { DownloadedFile(location: $0, mimeType: response?.mimeType) })
                    }.resume()
                },
                makeAttachment: { identifier, fileURL in
                    try UNNotificationAttachment(identifier: identifier, url: fileURL)
                },
                registerCarouselCategory: {
                    KlaviyoCategoryManager.shared.registerCategory(
                        categoryIdentifier: KlaviyoCategoryManager.carouselCategoryIdentifier,
                        actions: []
                    )
                },
                cancelDownloads: { session.invalidateAndCancel() }
            )
        }
    }

    enum Outcome {
        /// The content has the carousel category and at least ``KlaviyoCarouselParser/minimumCards`` attachments.
        case carousel(UNMutableNotificationContent)
        /// Too few images attached. The content is unchanged and should take the standard path.
        case fallback(UNMutableNotificationContent)
    }

    private let cards: [CarouselCardDefinition]
    private let content: UNMutableNotificationContent
    private let fallbackMediaType: String
    private let dependencies: Dependencies
    private let completion: (Outcome) -> Void
    private let lock = NSLock()
    private var attachments: [Int: UNNotificationAttachment] = [:]
    private var finished = false
    private var deadlineWorkItem: DispatchWorkItem?

    init(
        cards: [CarouselCardDefinition],
        content: UNMutableNotificationContent,
        fallbackMediaType: String,
        dependencies: Dependencies = .live(),
        completion: @escaping (Outcome) -> Void
    ) {
        self.cards = cards
        self.content = content
        self.fallbackMediaType = fallbackMediaType
        self.dependencies = dependencies
        self.completion = completion
    }

    func start(deadline: TimeInterval = batchDeadline) {
        // Registered while the images download, so delivery never waits on it. A push that falls back
        // leaves the category registered, which is harmless: it has no actions and is never pruned.
        dependencies.registerCarouselCategory()

        let group = DispatchGroup()
        for card in cards {
            group.enter()
            download(card) { group.leave() }
        }
        group.notify(queue: .global()) { [weak self] in self?.finish(cutShort: false) }
        let deadlineWorkItem = DispatchWorkItem { [weak self] in self?.finish(cutShort: true) }
        lock.lock()
        self.deadlineWorkItem = deadlineWorkItem
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + deadline, execute: deadlineWorkItem)
    }

    /// Delivers whatever has attached so far. Call from `serviceExtensionTimeWillExpire`.
    func finishNow() {
        finish(cutShort: true)
    }

    // MARK: - Private Methods

    private func download(_ card: CarouselCardDefinition, done: @escaping () -> Void) {
        dependencies.download(card.imageURL) { [weak self] file in
            defer { done() }
            guard let self else { return }
            guard let file else {
                if #available(iOS 14.0, *) {
                    Logger.carousel.warning("Carousel card \(card.position) image failed to download")
                }
                return
            }
            // Attachments need a file extension, and the downloaded file is deleted when this closure returns.
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension(for: card, mimeType: file.mimeType))
            do {
                try FileManager.default.moveItem(at: file.location, to: fileURL)
                let attachment = try dependencies.makeAttachment(
                    Self.attachmentIdentifierPrefix + String(card.position),
                    fileURL
                )
                if !record(attachment, position: card.position) {
                    // Arrived after delivery, so nothing will ever read it
                    try? FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                if #available(iOS 14.0, *) {
                    Logger.carousel.warning("Carousel card \(card.position) attachment failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// The server's MIME type wins, then a supported URL extension, then the integrator's fallback type.
    private func fileExtension(for card: CarouselCardDefinition, mimeType: String?) -> String {
        if let mimeType, let fileExtension = Self.imageFileExtensions[mimeType.lowercased()] {
            return fileExtension
        }
        let pathExtension = card.imageURL.pathExtension.lowercased()
        return Self.supportedPathExtensions.contains(pathExtension) ? pathExtension : fallbackMediaType
    }

    /// - Returns: `false` if the carousel was already delivered, so the attachment was not kept
    private func record(_ attachment: UNNotificationAttachment, position: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        attachments[position] = attachment
        return true
    }

    /// - Parameter cutShort: whether the deadline or the NSE's expiry ended the downloads
    private func finish(cutShort: Bool) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let attached = attachments.sorted { $0.key < $1.key }.map(\.value)
        deadlineWorkItem?.cancel()
        deadlineWorkItem = nil
        lock.unlock()

        dependencies.cancelDownloads()
        if cutShort, #available(iOS 14.0, *) {
            Logger.carousel.warning("Carousel downloads were cut short; delivering the \(attached.count) image(s) that attached.")
        }

        guard attached.count >= KlaviyoCarouselParser.minimumCards else {
            if #available(iOS 14.0, *) {
                Logger.carousel.warning("Only \(attached.count) carousel image(s) attached. Falling back to a standard notification.")
            }
            completion(.fallback(content))
            return
        }

        content.categoryIdentifier = KlaviyoCategoryManager.carouselCategoryIdentifier
        content.attachments = attached
        completion(.carousel(content))
    }
}

// MARK: - Content extension detection

extension KlaviyoCarouselHandler {
    /// Whether this app embeds a carousel content extension. The app bundle can't change while the
    /// NSE runs, so the PlugIns directory is scanned once per process.
    static let isContentExtensionInstalled = contentExtensionInstalled()

    /// Whether the host app embeds a notification content extension that handles the carousel category.
    ///
    /// Without one, a carousel push would show no buttons, because the carousel category has none.
    /// The NSE lives at `App.app/PlugIns/NSE.appex`, so its sibling appexes are the app's other extensions.
    static func contentExtensionInstalled(plugInsURL: URL = Bundle.main.bundleURL.deletingLastPathComponent()) -> Bool {
        let contents = try? FileManager.default.contentsOfDirectory(at: plugInsURL, includingPropertiesForKeys: nil)
        let appexes = contents ?? []
        return appexes.filter { $0.pathExtension == "appex" }.contains { appex in
            let extensionInfo = Bundle(url: appex)?.object(forInfoDictionaryKey: "NSExtension") as? [String: Any]
            let attributes = extensionInfo?["NSExtensionAttributes"] as? [String: Any]
            switch attributes?["UNNotificationExtensionCategory"] {
            case let category as String:
                return category == KlaviyoCategoryManager.carouselCategoryIdentifier
            case let categories as [String]:
                return categories.contains(KlaviyoCategoryManager.carouselCategoryIdentifier)
            default:
                return false
            }
        }
    }
}
