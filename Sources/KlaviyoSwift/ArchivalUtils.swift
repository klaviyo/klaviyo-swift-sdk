//
//  ArchiveUtils.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/26/22.
//

import Foundation

struct ArchiverClient {
    static let production = ArchiverClient(archivedData: NSKeyedArchiver.archivedData(withRootObject: requiringSecureCoding:))
    var archivedData: (Any, Bool) throws -> Data
}


func archiveQueue(queue: NSArray, to fileURL: URL) {
    guard let archiveData = try? environment.archiverClient.archivedData(queue, false) else {
        print("unable to archive the data to \(fileURL)")
        return
    }
    
    do {
        try environment.fileClient.write(archiveData, fileURL)
    } catch {
        print("Unable to write archive data to file at URL: \(fileURL)")
    }

}

func unarchiveFromFile(filePath: String)-> NSMutableArray? {
    guard let fileURL = environment.url(filePath),
            let archivedData = try? Data(contentsOf: fileURL) else {
        print("Unable to read archived data.")
        return nil
    }
    
     guard let unarchivedData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSMutableArray.self, from: archivedData) else {
         print("unable to unarchive data")
         return nil
    }
    
    if !removeFile(at: filePath) {
        print("Unable to remove archived data!")
    }
    return unarchivedData
}
