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

/// Klaviyo's namespaced subdirectory within `Library/Application Support`. Keeps our files
/// grouped and avoids colliding with the host app's own Application Support contents.
let klaviyoSupportSubdirectory = "com.klaviyo"

/// Resolves (creating on demand) `Library/Application Support/com.klaviyo` — the sanctioned home
/// for the SDK's internal support files. `Application Support` does not exist by default on iOS,
/// so it is created here with intermediate directories. Legacy files still live at the `Library`
/// root via `libraryDirectory`; migrating those is tracked separately (see issue #179).
func productionApplicationSupportDirectory() -> URL {
    let fileManager = FileManager.default
    let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent(klaviyoSupportSubdirectory, isDirectory: true)
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

public struct FileClient {
    public init(
        write: @escaping (Data, URL) throws -> Void,
        fileExists: @escaping (String) -> Bool,
        removeItem: @escaping (String) throws -> Void,
        libraryDirectory: @escaping () -> URL,
        applicationSupportDirectory: @escaping () -> URL
    ) {
        self.write = write
        self.fileExists = fileExists
        self.removeItem = removeItem
        self.libraryDirectory = libraryDirectory
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    public var write: (Data, URL) throws -> Void
    public var fileExists: (String) -> Bool
    public var removeItem: (String) throws -> Void
    /// Legacy `Library` root. Retained for pre-existing files (state/plist) not yet migrated.
    public var libraryDirectory: () -> URL
    /// Canonical home for new SDK support files: `Library/Application Support/com.klaviyo`.
    public var applicationSupportDirectory: () -> URL

    public static let production = FileClient(
        write: write(data:url:),
        fileExists: FileManager.default.fileExists(atPath:),
        removeItem: FileManager.default.removeItem(atPath:),
        libraryDirectory: { FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first! },
        applicationSupportDirectory: productionApplicationSupportDirectory
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

/// Load plist from the given bundle, or the main application bundle if none is specified.
/// - Parameters:
///   - name: the name of the plist
///   - bundle: the bundle to search; defaults to `Bundle.main`
/// - Returns: the contents of the plist or nil if not found
package func loadPlist(named name: String, in bundle: Bundle = .main) -> [String: AnyObject]? {
    guard let path = bundle.path(forResource: name, ofType: "plist"),
          let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] else {
        return nil
    }
    return dict
}
