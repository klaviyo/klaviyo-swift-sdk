//
//  String+Extensions.swift
//  KlaviyoCore
//
//  Created by Ajay Subramanya on 2026-02-23.
//

import Foundation

public extension String {
    /// Returns a pretty-printed JSON string with indentation, or the original string if parsing fails
    var prettyPrintedJSON: String {
        guard let data = data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return self
        }
        return prettyString
    }
}
