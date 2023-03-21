//
//  FileUtils.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/26/22.
//

import Foundation

func write(data: Data, url: URL) throws {
    try data.write(to: url, options: .atomic)
}

struct FileClient {
    static let production = FileClient(
        write: write(data:url:),
        fileExists: FileManager.default.fileExists(atPath:),
        removeItem: FileManager.default.removeItem(atPath:),
        libraryDirectory: { FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first! })
    var write: (Data, URL) throws -> Void
    var fileExists: (String) -> Bool
    var removeItem: (String) throws -> Void
    var libraryDirectory: () -> URL
}

/**
 filePathForData: returns a string representing the filepath where archived event queues are stored

 - Parameter apiKey: api key for distinguishing between sets of data
 - Parameter data: name representing the event queue to locate (will be either people or events)
 - Returns: filePath string representing the file location
 */
func filePathForData(apiKey: String, data: String) -> URL {
    let fileName = "klaviyo-\(apiKey)-\(data).plist"
    let directory = environment.fileClient.libraryDirectory()
    let filePath = directory.appendingPathComponent(fileName, isDirectory: false)
    return filePath
}

/**
 removeFile: remove the file at the specified path returns true if the file is removed, false otherwise

 - Parameter at: path of file to be removed
 - Returns: whether or not the file was removed
 */
func removeFile(at url: URL) -> Bool {
    if environment.fileClient.fileExists(url.path) {
        do {
            try environment.fileClient.removeItem(url.path)
            return true
        } catch {
            return false
        }
    }
    return false
}
