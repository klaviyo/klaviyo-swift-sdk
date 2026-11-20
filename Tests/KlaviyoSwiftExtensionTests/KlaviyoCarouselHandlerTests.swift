//
//  KlaviyoCarouselHandlerTests.swift
//

@testable import KlaviyoSwiftExtension
import Foundation
import UserNotifications
import XCTest

class KlaviyoCarouselHandlerTests: XCTestCase {
    /// A 1x1 transparent PNG, so `UNNotificationAttachment` accepts the file.
    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")!

    private var registeredCategoryCount = 0

    private func cards(_ count: Int) -> [CarouselCardDefinition] {
        (1...count).map { position in
            CarouselCardDefinition(
                position: position,
                imageURL: URL(string: "https://cdn.example.com/card-\(position).png")!,
                title: nil,
                description: nil,
                action: .openApp,
                url: nil
            )
        }
    }

    /// Writes a temporary PNG for each card whose position is in `succeeding`; the others fail.
    /// Positions in `pending` never call back, simulating a download that hangs.
    private func dependencies(succeeding: Set<Int>, pending: Set<Int> = []) -> KlaviyoCarouselHandler.Dependencies {
        KlaviyoCarouselHandler.Dependencies(
            download: { url, completion in
                let position = Int(url.deletingPathExtension().lastPathComponent.dropFirst("card-".count)) ?? 0
                guard !pending.contains(position) else { return }
                guard succeeding.contains(position) else {
                    completion(nil)
                    return
                }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try? Self.pngData.write(to: file)
                completion(file)
            },
            makeAttachment: { identifier, fileURL in
                try UNNotificationAttachment(identifier: identifier, url: fileURL)
            },
            registerCarouselCategory: { [weak self] in self?.registeredCategoryCount += 1 }
        )
    }

    private func run(
        cards: [CarouselCardDefinition],
        dependencies: KlaviyoCarouselHandler.Dependencies,
        deadline: TimeInterval = KlaviyoCarouselHandler.batchDeadline,
        finishNowAfter delay: TimeInterval? = nil
    ) -> KlaviyoCarouselHandler.Outcome? {
        let finished = expectation(description: "completion")
        var outcome: KlaviyoCarouselHandler.Outcome?
        var completionCount = 0
        let handler = KlaviyoCarouselHandler(
            cards: cards,
            content: UNMutableNotificationContent(),
            fallbackMediaType: "png",
            dependencies: dependencies
        ) {
            completionCount += 1
            outcome = $0
            finished.fulfill()
        }
        handler.start(deadline: deadline)
        if let delay {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { handler.finishNow() }
        }
        wait(for: [finished], timeout: 5)
        // Extra finishes after completion must not call it again.
        handler.finishNow()
        XCTAssertEqual(completionCount, 1)
        return outcome
    }

    func testAllImagesAttach_SetsCarouselCategoryAndOrderedAttachments() {
        let outcome = run(cards: cards(3), dependencies: dependencies(succeeding: [1, 2, 3]))

        guard case let .carousel(content) = outcome else { return XCTFail("Expected a carousel") }
        XCTAssertEqual(content.categoryIdentifier, KlaviyoCategoryManager.carouselCategoryIdentifier)
        XCTAssertEqual(content.attachments.map(\.identifier), ["card-1", "card-2", "card-3"])
        XCTAssertEqual(registeredCategoryCount, 1)
    }

    func testFailedImages_KeepTheirPositionsOutOfTheAttachments() {
        let outcome = run(cards: cards(5), dependencies: dependencies(succeeding: [1, 3, 5]))

        guard case let .carousel(content) = outcome else { return XCTFail("Expected a carousel") }
        XCTAssertEqual(content.attachments.map(\.identifier), ["card-1", "card-3", "card-5"])
    }

    func testFewerThanTwoImages_FallsBackWithoutCategoryOrAttachments() {
        let outcome = run(cards: cards(3), dependencies: dependencies(succeeding: [2]))

        guard case let .fallback(content) = outcome else { return XCTFail("Expected a fallback") }
        XCTAssertEqual(content.categoryIdentifier, "")
        XCTAssertTrue(content.attachments.isEmpty)
        XCTAssertEqual(registeredCategoryCount, 0)
    }

    func testDeadline_DeliversTheImagesThatAttached() {
        let outcome = run(
            cards: cards(3),
            dependencies: dependencies(succeeding: [1, 2], pending: [3]),
            deadline: 0.2
        )

        guard case let .carousel(content) = outcome else { return XCTFail("Expected a carousel") }
        XCTAssertEqual(content.attachments.map(\.identifier), ["card-1", "card-2"])
    }

    func testFinishNow_DeliversTheImagesThatAttached() {
        let outcome = run(
            cards: cards(3),
            dependencies: dependencies(succeeding: [1, 2], pending: [3]),
            finishNowAfter: 0.2
        )

        guard case let .carousel(content) = outcome else { return XCTFail("Expected a carousel") }
        XCTAssertEqual(content.attachments.count, 2)
    }

    // MARK: - Content extension detection

    func testContentExtensionInstalled_MatchesStringOrArrayCategory() throws {
        XCTAssertFalse(try contentExtensionInstalled(category: nil))
        XCTAssertFalse(try contentExtensionInstalled(category: "com.example.other"))
        let carousel = KlaviyoCategoryManager.carouselCategoryIdentifier
        XCTAssertTrue(try contentExtensionInstalled(category: carousel))
        XCTAssertTrue(try contentExtensionInstalled(category: ["com.example.other", carousel]))
    }

    /// Builds a PlugIns directory holding one appex whose Info.plist declares `category`.
    private func contentExtensionInstalled(category: Any?) throws -> Bool {
        let plugIns = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appex = plugIns.appendingPathComponent("Content.appex")
        try FileManager.default.createDirectory(at: appex, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plugIns) }

        var attributes: [String: Any] = [:]
        attributes["UNNotificationExtensionCategory"] = category
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.\(UUID().uuidString)",
            "CFBundlePackageType": "XPC!",
            "NSExtension": ["NSExtensionAttributes": attributes]
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: appex.appendingPathComponent("Info.plist"))

        return KlaviyoCarouselHandler.contentExtensionInstalled(plugInsURL: plugIns)
    }
}
