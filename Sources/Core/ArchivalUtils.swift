//
//  ArchiveUtils.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/26/22.
//

import Foundation

struct ArchiverClient {
    var archivedData: (Any, Bool) throws -> Data
    var unarchivedMutableArray: (Data) throws -> NSMutableArray?

    static let production = ArchiverClient(
        archivedData: NSKeyedArchiver.archivedData(withRootObject:requiringSecureCoding:),
        unarchivedMutableArray: { data in try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self,
                                                                                             NSDictionary.self,
                                                                                             NSString.self,
                                                                                             NSDate.self,
                                                                                             NSNull.self,
                                                                                             NSNumber.self,
                                                                                             NSURL.self],
                                                                                 from: data) as? NSMutableArray
        })
}

func archiveQueue(queue: NSArray, to fileURL: URL) {
    guard let archiveData = try? environment.archiverClient.archivedData(queue, true) else {
        print("unable to archive the data to \(fileURL)")
        return
    }

    do {
        try environment.fileClient.write(archiveData, fileURL)
    } catch {
        print("Unable to write archive data to file at URL: \(fileURL) error: \(error.localizedDescription)")
    }
}

func unarchiveFromFile(fileURL: URL) -> NSMutableArray? {
    guard environment.fileClient.fileExists(fileURL.path) else {
        print("Archive file not found.")
        return nil
    }
    guard let archivedData = try? environment.data(fileURL) else {
        print("Unable to read archived data.")
        return nil
    }

    guard let unarchivedData = try? environment.archiverClient.unarchivedMutableArray(archivedData) else {
        print("unable to unarchive data")
        return nil
    }

    if !removeFile(at: fileURL) {
        print("Unable to remove archived data!")
    }
    return unarchivedData
}
