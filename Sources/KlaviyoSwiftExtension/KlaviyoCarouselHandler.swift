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

    /// Downloads `url` to a temporary file, calling back with its location or nil on failure.
    /// The file is deleted when the callback returns.
    typealias Download = (_ url: URL, _ completion: @escaping (URL?) -> Void) -> Void

    struct Dependencies {
        var download: Download
        var makeAttachment: (_ identifier: String, _ fileURL: URL) throws -> UNNotificationAttachment
        var registerCarouselCategory: () -> Void

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
                        completion(location)
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
                }
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
        let group = DispatchGroup()
        for card in cards {
            group.enter()
            download(card) { group.leave() }
        }
        group.notify(queue: .global()) { [weak self] in self?.finish() }
        DispatchQueue.global().asyncAfter(deadline: .now() + deadline) { [weak self] in
            if #available(iOS 14.0, *) {
                Logger.carousel.warning("Carousel downloads passed the \(deadline)s deadline; delivering what attached.")
            }
            self?.finish()
        }
    }

    /// Delivers whatever has attached so far. Call from `serviceExtensionTimeWillExpire`.
    func finishNow() {
        finish()
    }

    // MARK: - Private Methods

    private func download(_ card: CarouselCardDefinition, done: @escaping () -> Void) {
        dependencies.download(card.imageURL) { [weak self] location in
            defer { done() }
            guard let self else { return }
            guard let location else {
                if #available(iOS 14.0, *) {
                    Logger.carousel.warning("Carousel card \(card.position) image failed to download")
                }
                return
            }
            // Attachments need a file extension, and the downloaded file is deleted when this closure returns.
            let pathExtension = card.imageURL.pathExtension.isEmpty ? fallbackMediaType : card.imageURL.pathExtension
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(pathExtension)
            do {
                try FileManager.default.moveItem(at: location, to: fileURL)
                let attachment = try dependencies.makeAttachment(
                    Self.attachmentIdentifierPrefix + String(card.position),
                    fileURL
                )
                record(attachment, position: card.position)
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.carousel.warning("Carousel card \(card.position) attachment failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func record(_ attachment: UNNotificationAttachment, position: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        attachments[position] = attachment
    }

    private func finish() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let attached = attachments.sorted { $0.key < $1.key }.map(\.value)
        lock.unlock()

        guard attached.count >= KlaviyoCarouselParser.minimumCards else {
            if #available(iOS 14.0, *) {
                Logger.carousel.warning("Only \(attached.count) carousel image(s) attached. Falling back to a standard notification.")
            }
            completion(.fallback(content))
            return
        }

        dependencies.registerCarouselCategory()
        content.categoryIdentifier = KlaviyoCategoryManager.carouselCategoryIdentifier
        content.attachments = attached
        completion(.carousel(content))
    }
}

// MARK: - Content extension detection

extension KlaviyoCarouselHandler {
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
