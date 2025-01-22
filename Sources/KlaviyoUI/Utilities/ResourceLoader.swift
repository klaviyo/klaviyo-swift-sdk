//
//  ResourceLoader.swift
//  KlaviyoSwiftUIWebView
//
//  Created by Andrew Balmer on 9/27/24.
//

import Foundation

enum ResourceLoaderError: Error {
    case notFound
}

enum ResourceLoader {
    static func getResourceUrl(path: String, type: String) throws -> URL {
        guard let fileUrl = Bundle.module.url(forResource: path, withExtension: type) else {
            throw ResourceLoaderError.notFound
        }

        return fileUrl
    }

    static func getResourceContents(path: String, type: String) throws -> String {
        guard let path = Bundle.module.path(forResource: path, ofType: type) else {
            throw ResourceLoaderError.notFound
        }

        do {
            let contents = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
            return contents
        } catch {
            throw error
        }
    }
}
