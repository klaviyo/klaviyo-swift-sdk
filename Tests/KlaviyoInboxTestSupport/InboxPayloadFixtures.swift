//
//  InboxPayloadFixtures.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation

/// Payloads as JSON, read with `JSONSerialization` so nested values bridge to `NSDictionary`,
/// `NSArray` and `NSNumber` the way APNs delivers them.
package enum InboxPayloadFixtures {
    package static let transmissionID = "01KV8CN3SH8N7MM5ZYNX40QCFH"

    /// Every field the parser reads, including an unknown action type in the middle of the buttons.
    package static let full = """
    {
      "aps": {
        "alert": {"title": "Sale", "body": "50% off"},
        "badge": 3,
        "mutable-content": 1,
        "content-available": 0,
        "sound": "default"
      },
      "body": {
        "_k": {
          "tm": "\(transmissionID)",
          "timestamp": "2026-10-08T12:00:00Z",
          "pt": "device-token",
          "$flow": "F1"
        },
        "action_buttons": [
          {"id": "a1", "action": "deep_link", "label": "Shop", "url": "myapp://sale"},
          {"id": "a2", "action": "snooze", "label": "Later"},
          {"id": "a3", "action": "open_url", "label": "Web", "url": "https://example.com"}
        ]
      },
      "url": "myapp://home",
      "web_url": "https://example.com/home",
      "rich-media": "https://example.com/i.png",
      "rich-media-type": "png",
      "key_value_pairs": {"k1": "v1", "n": 2},
      "badge_config": "set_count",
      "badge_value": 5,
      "notification_count": 7,
      "priority": "10"
    }
    """

    package static func userInfo(_ json: String) -> [AnyHashable: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            preconditionFailure("Invalid fixture JSON: \(json)")
        }
        return object
    }

    /// A Klaviyo payload with only `tm`, plus extra top-level JSON members (for example `"url": "x"`).
    package static func minimal(_ members: String = "") -> String {
        let extra = members.isEmpty ? "" : ", \(members)"
        return #"{"body": {"_k": {"tm": "\#(transmissionID)"}}\#(extra)}"#
    }
}
