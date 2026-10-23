//
//  StoreTestHelpers.swift
//  klaviyo-swift-sdk
//
//  Shared persistence helpers for store tests.
//

@testable import KlaviyoCore
import Foundation
import XCTest

/// The directory production store code writes to (`applicationSupportDirectory()` in production;
/// aliased to the library root by `FileIODouble`). Tests resolve persisted files through this so
/// their assertions exercise the real write path instead of passing vacuously against the default.
func storeDirectory() -> URL {
    environment.fileClient.applicationSupportDirectory()
}

/// Swaps in a `FileClient` with distinct library/app-support roots, runs `perform`, and asserts
/// the resulting write landed under the app-support root rather than the library root. Shared by
/// SDKConfigStore/IdentityStore's "new files route to Application Support" tests.
func assertWriteRoutesToApplicationSupport(
    fileName: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    perform: () -> Void
) {
    let appSupportRoot = URL(fileURLWithPath: "/tmp/klaviyo-appsupport-routing-tests/app-support")
    let libraryRoot = URL(fileURLWithPath: "/tmp/klaviyo-appsupport-routing-tests/library")
    var capturedURL: URL?

    environment.fileClient = FileClient(
        write: { _, fileURL in capturedURL = fileURL },
        fileExists: { _ in false },
        removeItem: { _ in },
        libraryDirectory: { libraryRoot },
        applicationSupportDirectory: { appSupportRoot }
    )

    perform()

    XCTAssertEqual(capturedURL, appSupportRoot.appendingPathComponent(fileName), file: file, line: line)
    XCTAssertFalse(capturedURL?.path.hasPrefix(libraryRoot.path) ?? true, file: file, line: line)
}
