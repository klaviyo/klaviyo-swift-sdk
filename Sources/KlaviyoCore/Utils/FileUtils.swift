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

public struct FileClient: Sendable {
    public init(
        write: @Sendable @escaping (Data, URL) throws -> Void,
        fileExists: @Sendable @escaping (String) -> Bool,
        removeItem: @Sendable @escaping (String) throws -> Void,
        libraryDirectory: @Sendable @escaping () -> URL) {
        self.write = write
        self.fileExists = fileExists
        self.removeItem = removeItem
        self.libraryDirectory = libraryDirectory
    }

    public var write: @Sendable (Data, URL) throws -> Void
    public var fileExists: @Sendable (String) -> Bool
    public var removeItem: @Sendable (String) throws -> Void
    public var libraryDirectory: @Sendable () -> URL

    public static let production = FileClient(
        write: write(data:url:),
        fileExists: { path in
            FileManager.default.fileExists(atPath: path)
        },
        removeItem: { path in
            try FileManager.default.removeItem(atPath: path)
        },
        libraryDirectory: {
            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        })
}

/**
 filePathForData: returns a string representing the filepath where archived event queues are stored

 - Parameter apiKey: api key for distinguishing between sets of data
 - Parameter data: name representing the event queue to locate (will be either people or events)
 - Returns: filePath string representing the file location
 */
public func filePathForData(apiKey: String, data: String) -> URL {
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
public func removeFile(fileClient: FileClient, at url: URL) -> Bool {
    if fileClient.fileExists(url.path) {
        do {
            try fileClient.removeItem(url.path)
            return true
        } catch {
            return false
        }
    }
    return false
}

/// load any plist from app main bundle
/// - Parameter name: the name of the plist
/// - Returns: the contents of the plist in `[String: AnyObject]` or nil if not found
func loadPlist(named name: String) -> [String: AnyObject]? {
    if let path = Bundle.main.path(forResource: name, ofType: "plist"),
       let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
        return dict
    }
    return nil
}
