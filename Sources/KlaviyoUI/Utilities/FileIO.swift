//
//  FileIO.swift
//  KlaviyoSwiftUIWebView
//
//  Created by Andrew Balmer on 9/27/24.
//

import Foundation

enum FileIOError: Error {
    case notFound
}

enum FileIO {
    static func getFileContents(path: String, type: String) throws -> String {
        guard let path = Bundle.module.path(forResource: path, ofType: type) else {
            throw FileIOError.notFound
        }

        do {
            let contents = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
            return contents
        } catch {
            throw error
        }
    }
}
