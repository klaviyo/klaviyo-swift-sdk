//
//  IAFWebViewModelTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/6/25.
//

@testable @_spi(KlaviyoPrivate) import KlaviyoForms
import KlaviyoCore
import WebKit
import XCTest

final class IAFWebViewModelPreloadingTests: XCTestCase {
    // MARK: - setup

    var viewModel: IAFWebViewModel!
    var delegate: MockIAFWebViewDelegate!

    override func setUp() {
        super.setUp()

        viewModel = IAFWebViewModel(url: URL(string: "https://example.com")!)
        delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
    }

    override func tearDown() {
        viewModel = nil
        delegate = nil

        super.tearDown()
    }

    // MARK: - tests

    /// Tests scenario in which a `formWillAppear` event is emitted before the timeout is reached.
    func testPreloadWebsiteSuccess() async throws {
        // Given
        delegate.preloadResult = .formWillAppear(delay: 100_000_000) // 0.1 second in nanoseconds
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

    /// Tests scenario in which the timeout is reached before the `formWillAppear` event is emitted.
    func testPreloadWebsiteTimeout() async {
        // Given
        delegate.preloadResult = .formWillAppear(delay: 1_000_000_000) // 1 second in nanoseconds
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

    /// Tests scenario in which the delegate does nothing and emits no events after `preloadUrl()` is called.
    func testPreloadWebsiteNoActionTimeout() async {
        // Given
        delegate.preloadResult = MockIAFWebViewDelegate.PreloadResult.none
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
}
