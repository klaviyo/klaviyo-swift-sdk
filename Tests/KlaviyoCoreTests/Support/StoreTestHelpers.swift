//
//  StoreTestHelpers.swift
//  klaviyo-swift-sdk
//
//  Shared persistence helpers for store tests.
//

@testable import KlaviyoCore
import Foundation

/// The directory production store code writes to (`applicationSupportDirectory()` in production;
/// aliased to the library root by `FileIODouble`). Tests resolve persisted files through this so
/// their assertions exercise the real write path instead of passing vacuously against the default.
func storeDirectory() -> URL {
    environment.fileClient.applicationSupportDirectory()
}
