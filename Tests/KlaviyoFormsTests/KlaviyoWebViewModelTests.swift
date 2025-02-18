//
//  KlaviyoWebViewModelTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 1/21/25.
//

@testable @_spi(KlaviyoPrivate) import KlaviyoForms
import WebKit
import XCTest

class MockKlaviyoWebViewDelegate: NSObject, KlaviyoWebViewDelegate {
    enum PreloadResult {
        case didFinishNavigation(delay: UInt64)
        case didFailNavigation(delay: UInt64)
    }

    let viewModel: KlaviyoWebViewModel

    var preloadResult: PreloadResult?
    var preloadUrlCalled = false
    var evaluateJavaScriptCalled = false

    init(viewModel: KlaviyoWebViewModel) {
        self.viewModel = viewModel
    }

    func preloadUrl() {
        viewModel.handleNavigationEvent(.didCommitNavigation)
        preloadUrlCalled = true

        Task {
            if let result = preloadResult {
                switch result {
                case let .didFinishNavigation(delay):
                    try? await Task.sleep(nanoseconds: delay)
                    viewModel.handleNavigationEvent(.didFinishNavigation)
                case let .didFailNavigation(delay):
                    try? await Task.sleep(nanoseconds: delay)
                    viewModel.handleNavigationEvent(.didFailNavigation)
                }
            }
        }
    }

    func evaluateJavaScript(_ script: String) async throws -> Any {
        evaluateJavaScriptCalled = true
        return true
    }

    func dismiss() {}
}

final class KlaviyoWebViewModelTests: XCTestCase {
    // MARK: - setup

    var viewModel: KlaviyoWebViewModel!
    var delegate: MockKlaviyoWebViewDelegate!

    override func setUp() {
        super.setUp()

        viewModel = KlaviyoWebViewModel(url: URL(string: "https://example.com")!)
        delegate = MockKlaviyoWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
    }

    override func tearDown() {
        viewModel = nil
        delegate = nil

        super.tearDown()
    }

    // MARK: - tests

    func testPreloadWebsiteSuccess() async throws {
        // Given
        delegate.preloadResult = .didFinishNavigation(delay: 100_000_000) // 0.1 second in nanoseconds
        let expectation = XCTestExpectation(description: "Preloading website succeeds")

        // When
        do {
            try await viewModel.preloadWebsite(timeout: 1_000_000_000) // 1 second in nanoseconds
            expectation.fulfill()
        } catch {
            XCTFail("Expected success, but got error: \(error)")
        }

        // Then
        XCTAssertTrue(delegate.preloadUrlCalled, "preloadUrl should be called on delegate")
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testPreloadWebsiteTimeout() async {
        // Given
        delegate.preloadResult = .didFinishNavigation(delay: 1_000_000_000) // 1 second in nanoseconds
        let expectation = XCTestExpectation(description: "Preloading website times out")

        // When
        do {
            try await viewModel.preloadWebsite(timeout: 100_000_000) // 0.1 second in nanoseconds
            XCTFail("Expected timeout error, but succeeded")
        } catch PreloadError.timeout {
            expectation.fulfill()
        } catch {
            XCTFail("Expected timeout error, but got: \(error)")
        }

        // Then
        XCTAssertTrue(delegate.preloadUrlCalled, "preloadUrl should be called on delegate")
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testPreloadWebsiteNavigationFailed() async {
        // Given
        delegate.preloadResult = .didFailNavigation(delay: 100_000_000) // 0.1 second in nanoseconds
        let expectation = XCTestExpectation(description: "Preloading website fails")

        // When
        do {
            try await viewModel.preloadWebsite(timeout: 1_000_000_000) // 1 second in nanoseconds
            XCTFail("Expected navigation failed error, but succeeded")
        } catch PreloadError.navigationFailed {
            expectation.fulfill()
        } catch {
            XCTFail("Expected navigation failed error, but got: \(error)")
        }

        // Then
        XCTAssertTrue(delegate.preloadUrlCalled, "preloadUrl should be called on delegate")
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
