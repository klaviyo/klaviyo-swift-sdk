//
//  ArchivalUtils.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/26/22.
//

import Foundation

public struct ArchiverClient: @unchecked Sendable {
    public init(
        archivedData: @escaping (Any, Bool) throws -> Data,
        unarchivedMutableArray: @escaping (Data) throws -> NSMutableArray?
    ) {
        self.archivedData = archivedData
        self.unarchivedMutableArray = unarchivedMutableArray
    }

    public var archivedData: (Any, Bool) throws -> Data
    public var unarchivedMutableArray: (Data) throws -> NSMutableArray?

    public static let production = ArchiverClient(
        archivedData: NSKeyedArchiver.archivedData(withRootObject:requiringSecureCoding:),
        unarchivedMutableArray: { data in try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self,
                                                                                             NSDictionary.self,
                                                                                             NSString.self,
                                                                                             NSDate.self,
                                                                                             NSNull.self,
                                                                                             NSNumber.self,
                                                                                             NSURL.self],
                                                                                 from: data) as? NSMutableArray
        }
    )
}

public func archiveQueue(fileClient: FileClient, queue: NSArray, to fileURL: URL) {
    guard let archiveData = try? environment.archiverClient.archivedData(queue, true) else {
        print("unable to archive the data to \(fileURL)")
        return
    }

    do {
        try fileClient.write(archiveData, fileURL)
    } catch {
        print("Unable to write archive data to file at URL: \(fileURL) error: \(error.localizedDescription)")
    }
}

public func unarchiveFromFile(fileClient: FileClient, fileURL: URL) -> NSMutableArray? {
    guard fileClient.fileExists(fileURL.path) else {
        print("Archive file not found.")
        return nil
    }
    guard let archivedData = try? environment.dataFromUrl(fileURL) else {
        print("Unable to read archived data.")
        return nil
    }

    guard let unarchivedData = try? environment.archiverClient.unarchivedMutableArray(archivedData) else {
        print("unable to unarchive data")
        return nil
    }

    if !removeFile(fileClient: environment.fileClient, at: fileURL) {
        print("Unable to remove archived data!")
    }
    return unarchivedData
}
