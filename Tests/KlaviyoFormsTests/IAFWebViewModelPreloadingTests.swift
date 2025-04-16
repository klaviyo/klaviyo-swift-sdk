@testable import KlaviyoForms
import KlaviyoCore
import WebKit
import XCTest

final class IAFWebViewModelPreloadingTests: XCTestCase {
    // MARK: - setup

    var viewModel: IAFWebViewModel!
    var delegate: MockIAFWebViewDelegate!

    @MainActor
    override func setUp() {
        super.setUp()

        // Initialize these later in the test methods
        viewModel = nil
        delegate = nil
    }

    override func tearDown() {
        viewModel = nil
        delegate = nil

        super.tearDown()
    }

    // Helper method to set up the viewModel on the main actor
    @MainActor
    private func setUpViewModel() {
        viewModel = IAFWebViewModel(url: URL(string: "https://example.com")!, companyId: "abc123")
        delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
    }

    // MARK: - tests

    /// Tests scenario in which a `formWillAppear` event is emitted before the timeout is reached.
    @MainActor
    func testPreloadWebsiteSuccess() async throws {
        // Given
        setUpViewModel()
        delegate.handshakeResult = .handshakeEstablished(delay: 0.1)
        let expectation = XCTestExpectation(description: "Preloading website succeeds")

        // When
        do {
            try await viewModel.establishHandshake(timeout: 1.0)
            expectation.fulfill()
        } catch {
            XCTFail("Expected success, but got error: \(error)")
        }

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    /// Tests scenario in which the timeout is reached before the `formWillAppear` event is emitted.
    @MainActor
    func testPreloadWebsiteTimeout() async {
        // Given
        setUpViewModel()
        delegate.handshakeResult = .handshakeEstablished(delay: 1.0)
        let expectation = XCTestExpectation(description: "Preloading website times out")

        // When
        do {
            try await viewModel.establishHandshake(timeout: 0.1)
            XCTFail("Expected timeout error, but succeeded")
        } catch TimeoutError.timeout {
            expectation.fulfill()
        } catch {
            XCTFail("Expected timeout error, but got: \(error)")
        }

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    /// Tests scenario in which the delegate does nothing and emits no events after `preloadUrl()` is called.
    @MainActor
    func testPreloadWebsiteNoActionTimeout() async {
        // Given
        setUpViewModel()
        delegate.handshakeResult = MockIAFWebViewDelegate.HandshakeResult.none
        let expectation = XCTestExpectation(description: "Preloading website times out")

        // When
        do {
            try await viewModel.establishHandshake(timeout: 0.1)
            XCTFail("Expected timeout error, but succeeded")
        } catch TimeoutError.timeout {
            expectation.fulfill()
        } catch {
            XCTFail("Expected timeout error, but got: \(error)")
        }

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
