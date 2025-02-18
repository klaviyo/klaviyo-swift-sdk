//
//  ResourceLoader.swift
//  KlaviyoSwiftUIWebView
//
//  Created by Andrew Balmer on 9/27/24.
//

#if DEBUG
import Foundation
import OSLog

enum ResourceLoaderError: Error {
    case resourceNotFound
    case bundleError
}

enum ResourceLoader {
    /// The name of the resource bundle specified in the podspec.
    private static let resourceBundleName = "KlaviyoFormsResources"

    static func getResourceUrl(path: String, type: String) throws -> URL {
        let bundle = try resourceBundle()

        guard let resourceUrl = bundle.url(forResource: path, withExtension: type) else {
            if #available(iOS 14.0, *) {
                Logger.filesystem.warning("Unable to locate URL for resource '\(path).\(type)'. Check that the resource exists within the bundle.")
            }
            throw ResourceLoaderError.resourceNotFound
        }

        return resourceUrl
    }

    static func getResourceContents(path: String, type: String) throws -> String {
        let bundle = try resourceBundle()

        guard let resourcePath = bundle.path(forResource: path, ofType: type) else {
            if #available(iOS 14.0, *) {
                Logger.filesystem.warning("Unable to locate path for resource '\(path).\(type)'. Check that the resource exists within the bundle.")
            }
            throw ResourceLoaderError.resourceNotFound
        }

        do {
            let contents = try String(contentsOfFile: resourcePath, encoding: .utf8)
            return contents
        } catch {
            if #available(iOS 14.0, *) {
                Logger.filesystem.warning("Unable to cast file contents for resource '\(path).\(type)' to type String")
            }
            throw error
        }
    }

    // Determines the appropriate bundle based on the build system
    private static func resourceBundle() throws -> Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        do {
            return try Bundle(for: BundleLocator.self).resourceBundle(named: resourceBundleName)
        } catch {
            throw ResourceLoaderError.bundleError
        }
        #endif
    }
}

// Helper class for locating the resource bundle (CocoaPods)
private class BundleLocator {}

extension Bundle {
    fileprivate func resourceBundle(named name: String) throws -> Bundle {
        guard let bundleUrl = url(forResource: name, withExtension: "bundle"),
              let bundle = Bundle(url: bundleUrl) else {
            if #available(iOS 14.0, *) {
                Logger.filesystem.warning("Unable to locate bundle named '\(name)'")
            }
            throw ResourceLoaderError.bundleError
        }

        return bundle
    }
}
#endif
