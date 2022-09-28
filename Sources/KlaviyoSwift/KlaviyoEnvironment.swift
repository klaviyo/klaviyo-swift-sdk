//
//  KlaviyoEnvironment.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/28/22.
//

import Foundation

var environment = KlaviyoEnvironment.production

struct KlaviyoEnvironment {
    var archiverClient: ArchiverClient
    var fileClient: FileClient
    var url: (String) -> URL?
    var data: (URL) throws -> Data
    static let production = KlaviyoEnvironment(
        archiverClient: ArchiverClient.production,
        fileClient: FileClient.production,
        url: URL.init(string:),
        data: { url in try Data(contentsOf: url) }
    )

}
