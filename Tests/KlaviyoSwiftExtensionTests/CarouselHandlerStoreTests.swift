//
//  CarouselHandlerStoreTests.swift
//

@testable import KlaviyoSwiftExtension
import UserNotifications
import XCTest

class CarouselHandlerStoreTests: XCTestCase {
    private let store = CarouselHandlerStore()

    private func makeHandler() -> KlaviyoCarouselHandler {
        KlaviyoCarouselHandler(
            cards: [],
            content: UNMutableNotificationContent(),
            fallbackMediaType: "jpg",
            dependencies: KlaviyoCarouselHandler.Dependencies(
                download: { _, _ in },
                makeAttachment: { _, _ in throw CocoaError(.fileNoSuchFile) },
                registerCarouselCategory: {},
                cancelDownloads: {}
            ),
            completion: { _ in }
        )
    }

    private func isDelivered(_ identifier: String) -> Bool {
        if case .delivered = store.state(for: identifier) { return true }
        return false
    }

    func testMarkDelivered_RecordsTheAttemptThatIsDownloading() {
        let attempt = CarouselHandlerStore.Attempt()
        store.insert(makeHandler(), attempt: attempt, for: "offer")

        store.markDelivered("offer", attempt: attempt)

        XCTAssertTrue(isDelivered("offer"))
    }

    func testReset_ForgetsAnEarlierDeliveredCarousel() {
        let attempt = CarouselHandlerStore.Attempt()
        store.insert(makeHandler(), attempt: attempt, for: "offer")
        store.markDelivered("offer", attempt: attempt)

        // A new request with the same identifier (apns-collapse-id) arrives
        store.reset("offer")

        XCTAssertNil(store.state(for: "offer"))
    }

    func testMarkDelivered_IgnoresAnAttemptANewerRequestReplaced() {
        let earlier = CarouselHandlerStore.Attempt()
        let later = CarouselHandlerStore.Attempt()
        store.insert(makeHandler(), attempt: earlier, for: "offer")
        store.reset("offer")
        store.insert(makeHandler(), attempt: later, for: "offer")

        store.markDelivered("offer", attempt: earlier)

        guard case let .downloading(_, current) = store.state(for: "offer") else {
            return XCTFail("The later carousel should still be downloading")
        }
        XCTAssertTrue(current === later)
    }
}
