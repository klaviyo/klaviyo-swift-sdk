//
//  ResourceLoader.swift
//  KlaviyoSwiftUIWebView
//
//  Created by Andrew Balmer on 9/27/24.
//

#if DEBUG
import Foundation

enum ResourceLoaderError: Error {
    case resourceNotFound
}

enum ResourceLoader {
    static func getResourceUrl(path: String, type: String) throws -> URL {
        let bundle = resourceBundle()

        guard let resourceUrl = bundle?.url(forResource: path, withExtension: type) else {
            throw ResourceLoaderError.resourceNotFound
        }

        return resourceUrl
    }

    static func getResourceContents(path: String, type: String) throws -> String {
        let bundle = resourceBundle()

        guard let resourcePath = bundle?.path(forResource: path, ofType: type) else {
            throw ResourceLoaderError.resourceNotFound
        }

        do {
            let contents = try String(contentsOfFile: resourcePath, encoding: .utf8)
            return contents
        } catch {
            throw error
        }
    }

    // Determines the appropriate bundle based on the build system
    private static func resourceBundle() -> Bundle? {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: BundleLocator.self).resourceBundle(named: "KlaviyoUIResources")
        #endif
    }
}

// Helper class for locating the resource bundle (CocoaPods)
private class BundleLocator {}

extension Bundle {
    fileprivate func resourceBundle(named name: String) -> Bundle? {
        guard let bundleUrl = url(forResource: name, withExtension: "bundle"),
              let bundle = Bundle(url: bundleUrl) else {
            return nil
        }

        return bundle
    }
}
#endif
