//
//  Profile+Enqueuer.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/26/26.
//

import Foundation

extension Profile {
    /// The custom-properties dictionary passed to `RequestEnqueuer.enqueueProfile(properties:)`
    /// on the pre-init buffer path.
    ///
    /// The ungated `RequestEnqueuer.enqueueProfile(properties:)` builds a Model-1 payload from the
    /// current `IdentityStore` identity plus a flat `[String: Any]` `properties` map. Only the
    /// profile's identifiers (email/phoneNumber/externalId — sourced from `IdentityStore`) and its
    /// custom `properties` reach the buffered payload. Structured attributes (firstName, lastName,
    /// title, organization, image, location) have no slot in that payload and are dropped on the
    /// pre-init path — an accepted edge documented in MAGE-952.
    var enqueuerProperties: [String: Any] {
        properties
    }

    /// Returns `true` when the profile carries structured attributes that the pre-init buffer path
    /// cannot represent. The Model-1 `RequestEnqueuer` payload has slots only for identifiers and
    /// the flat custom-`properties` dict; firstName, lastName, title, organization, image, and
    /// location are silently dropped before `initialize()` is called.
    ///
    /// Profiles with only identifiers (email/phoneNumber/externalId) and/or flat `properties`
    /// return `false` — those are fully represented in the buffered payload.
    var hasDroppableStructuredAttributes: Bool {
        firstName != nil
            || lastName != nil
            || title != nil
            || organization != nil
            || image != nil
            || location != nil
    }
}
