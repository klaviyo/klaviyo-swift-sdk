//
//  IAFWebViewModelTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/6/25.
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
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

        viewModel = IAFWebViewModel(url: URL(string: "https://example.com")!, apiKey: "abc123", profileData: nil)
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
    @MainActor
    func testPreloadWebsiteSuccess() async {
        // Given
        delegate.handshakeResult = .handshakeEstablished(delay: 0)

        // When / Then - the handshake is awaited directly, so no separate
        // expectation/fulfillment is needed.
        //
        // The handshake is mocked with zero delay, so this budget only bounds a hang.
        // It is generous so a stalled scheduler on a loaded runner cannot fail the test.
        // Do not raise it much further: XCTest kills a test at its 120s execution
        // allowance, and a stall that long is tracked separately (MAGE-1321).
        do {
            try await viewModel.establishHandshake(timeout: 30.0)
        } catch {
            XCTFail("Expected success, but got error: \(error)")
        }
    }

    /// Tests scenario in which the timeout is reached before the `formWillAppear` event is emitted.
    @MainActor
    func testPreloadWebsiteTimeout() async {
        // Given - the handshake arrives later than the timeout allows
        delegate.handshakeResult = .handshakeEstablished(delay: 1.0)

        // When / Then - establishHandshake must surface a timeout. The throw is
        // awaited directly, so no separate expectation/fulfillment is needed.
        //
        // 0.1 must stay well under the 1.0 mock delay above. Raising it past that
        // inverts the race and the test stops asserting anything.
        do {
            try await viewModel.establishHandshake(timeout: 0.1)
            XCTFail("Expected timeout error, but succeeded")
        } catch TimeoutError.timeout {
            // expected
        } catch {
            XCTFail("Expected timeout error, but got: \(error)")
        }
    }

    /// Tests scenario in which the delegate does nothing and emits no events after `preloadUrl()` is called.
    @MainActor
    func testPreloadWebsiteNoActionTimeout() async {
        // Given - the delegate emits no events after preloadUrl()
        delegate.handshakeResult = MockIAFWebViewDelegate.HandshakeResult.none

        // When / Then - establishHandshake must surface a timeout rather than hang.
        // The throw is awaited directly, so no separate expectation/fulfillment is needed.
        //
        // Expiring is the expected result, so a small timeout keeps this fast and
        // immune to runner load.
        do {
            try await viewModel.establishHandshake(timeout: 0.1)
            XCTFail("Expected timeout error, but succeeded")
        } catch TimeoutError.timeout {
            // expected
        } catch {
            XCTFail("Expected timeout error, but got: \(error)")
        }
    }
}
