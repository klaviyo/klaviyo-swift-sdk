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

public struct FileClient {
    public init(
        write: @escaping (Data, URL) throws -> Void,
        fileExists: @escaping (String) -> Bool,
        removeItem: @escaping (String) throws -> Void,
        libraryDirectory: @escaping () -> URL
    ) {
        self.write = write
        self.fileExists = fileExists
        self.removeItem = removeItem
        self.libraryDirectory = libraryDirectory
    }

    public var write: (Data, URL) throws -> Void
    public var fileExists: (String) -> Bool
    public var removeItem: (String) throws -> Void
    public var libraryDirectory: () -> URL

    public static let production = FileClient(
        write: write(data:url:),
        fileExists: FileManager.default.fileExists(atPath:),
        removeItem: FileManager.default.removeItem(atPath:),
        libraryDirectory: { FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first! }
    )
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
public func removeFile(at url: URL) -> Bool {
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

/// load any plist from app main bundle or React Native framework bundle
/// - Parameter name: the name of the plist
/// - Returns: the contents of the plist in `[String: AnyObject]` or nil if not found
func loadPlist(named name: String) -> [String: AnyObject]? {
    let plistPath: String? = {
        if let path = Bundle.main.path(forResource: name, ofType: "plist") {
            // Try loading from main bundle first
            return path
        } else if let reactNativeBundle = Bundle(identifier: "org.cocoapods.klaviyo-react-native-sdk"),
                  let path = reactNativeBundle.path(forResource: name, ofType: "plist") {
            // If not found in main bundle, try loading from React Native framework bundle
            return path
        } else {
            return nil
        }
    }()

    if let plistPath,
       let dict = NSDictionary(contentsOfFile: plistPath) as? [String: AnyObject] {
        return dict
    } else {
        return nil
    }
}
