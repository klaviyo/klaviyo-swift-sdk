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
        libraryDirectory: @escaping () -> URL,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        copyItem: @escaping (String, String) throws -> Void
    ) {
        self.write = write
        self.fileExists = fileExists
        self.removeItem = removeItem
        self.libraryDirectory = libraryDirectory
        self.createDirectory = createDirectory
        self.copyItem = copyItem
    }

    public var write: (Data, URL) throws -> Void
    public var fileExists: (String) -> Bool
    public var removeItem: (String) throws -> Void
    public var libraryDirectory: () -> URL
    public var createDirectory: (URL, Bool) throws -> Void
    public var copyItem: (String, String) throws -> Void

    public static let production = FileClient(
        write: write(data:url:),
        fileExists: FileManager.default.fileExists(atPath:),
        removeItem: FileManager.default.removeItem(atPath:),
        libraryDirectory: { FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first! },
        createDirectory: { url, withIntermediateDirectories in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: nil)
        },
        copyItem: { atPath, toPath in
            try FileManager.default.copyItem(atPath: atPath, toPath: toPath)
        }
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

/// Load plist from main application bundle
/// - Parameter name: the name of the plist
/// - Returns: the contents of the plist or nil if not found
package func loadPlist(named name: String) -> [String: AnyObject]? {
    guard let path = Bundle.main.path(forResource: name, ofType: "plist"),
          let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] else {
        return nil
    }
    return dict
}

/// Load plist from React Native SDK bundle (for dynamic linking scenarios)
/// - Parameter name: the name of the plist
/// - Returns: the contents of the plist or nil if not found
package func loadPlistFromReactNativeBundle(named name: String) -> [String: AnyObject]? {
    guard let bundle = Bundle(identifier: "org.cocoapods.klaviyo-react-native-sdk"),
          let path = bundle.path(forResource: name, ofType: "plist"),
          let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] else {
        return nil
    }
    return dict
}
