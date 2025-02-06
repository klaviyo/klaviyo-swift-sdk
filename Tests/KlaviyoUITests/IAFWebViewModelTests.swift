//
//  IAFWebViewModelTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/6/25.
//

@testable @_spi(KlaviyoPrivate) import KlaviyoUI
import KlaviyoCore
import WebKit
import XCTest

final class IAFWebViewModelTests: XCTestCase {
    // MARK: - setup

    var viewModel: IAFWebViewModel!
    var viewController: KlaviyoWebViewController!

    override func setUpWithError() throws {
        super.setUp()

        environment.sdkName = { "swift" }
        environment.sdkVersion = { "0.0.1" }

        let fileUrl = try ResourceLoader.getResourceUrl(path: "IAFUnitTest", type: "html")

        viewModel = IAFWebViewModel(url: fileUrl)
        viewController = KlaviyoWebViewController(viewModel: viewModel)
    }

    override func tearDown() {
        viewModel = nil
        viewController = nil

        super.tearDown()
    }
}
