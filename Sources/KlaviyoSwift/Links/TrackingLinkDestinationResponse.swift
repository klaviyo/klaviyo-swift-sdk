//
//  TrackingLinkDestinationResponse.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 7/31/25.
//

import Foundation
import OSLog

/// A struct to decode the response from a tracking link resolution request
///
/// When an API call is made to a tracking link URL, the engtrack service will
/// respond JSON including the canonical universal link URL. This model allows
/// us to decode that JSON so we can access the universal link URL.
struct TrackingLinkDestinationResponse: Decodable {
    /// The canonical universal link URL indicating the tracking link's ultimate destination.
    let destinationLink: URL

    private enum CodingKeys: String, CodingKey {
        case destinationLink = "original_destination"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let urlString = try container.decode(String.self, forKey: .destinationLink)

        guard let url = URL(string: urlString) else {
            let errorMessage = "Unable to initialize URL from string '\(urlString)'"
            if #available(iOS 14.0, *) {
                Logger.codableLogger.warning("\(errorMessage)")
            }
            throw DecodingError.dataCorruptedError(
                forKey: .destinationLink,
                in: container,
                debugDescription: errorMessage
            )
        }
        destinationLink = url
    }
}
