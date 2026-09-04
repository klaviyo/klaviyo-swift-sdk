//
//  KlaviyoState+RequestBuilding.swift
//
//
//  Created by Isobelle Lim on 8/27/26.
//

import AnyCodable
import Foundation
import KlaviyoCore

// MARK: - Request-building helpers

extension KlaviyoState {
    /// Resolves the profile for a token request, folding in and consuming any pending profile.
    private mutating func resolveAndConsumePendingProfile() -> Profile {
        let profile: Profile
        if let pendingProfile {
            profile = Profile.updateProfileWithProperties(
                email: email, phoneNumber: phoneNumber, externalId: externalId, dict: pendingProfile
            )
            self.pendingProfile = nil
        } else {
            profile = Profile(email: email, phoneNumber: phoneNumber, externalId: externalId)
        }
        return profile
    }

    /// Builds a `ProfilePayload` from the incoming profile, overriding its identifiers with the
    /// canonical values already resolved onto state. Shared by the pre-init and initialized
    /// `enqueueProfile` branches so their payloads cannot diverge.
    func profilePayload(from profile: Profile, anonymousId: String) -> ProfilePayload {
        ProfilePayload(
            profile,
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            anonymousId: anonymousId
        )
    }

    /// Builds a push-token registration request, resolving (and consuming) any pending profile.
    /// The `resolved` prefix marks the state-sourcing layer over the pure `RequestFactory.tokenRequest`.
    mutating func resolvedTokenRequest(
        apiKey: String,
        anonymousId: String,
        pushToken: String,
        enablement: PushEnablement
    ) -> KlaviyoRequest {
        RequestFactory.tokenRequest(
            apiKey: apiKey,
            pushToken: pushToken,
            enablement: enablement,
            background: environment.getBackgroundSetting().rawValue,
            profile: ProfilePayload(resolveAndConsumePendingProfile(), anonymousId: anonymousId)
        )
    }

    mutating func enqueueProfileOrTokenRequest() {
        guard let apiKey = apiKey,
              let anonymousId = anonymousId else {
            environment.emitDeveloperWarning("SDK internal error")
            return
        }
        // if we have push data and we are switching emails
        // we want to associate the token with the new email.
        if let pushTokenData = pushTokenData {
            self.pushTokenData = nil
            let request = resolvedTokenRequest(
                apiKey: apiKey,
                anonymousId: anonymousId,
                pushToken: pushTokenData.pushToken,
                enablement: pushTokenData.pushEnablement
            )
            enqueueRequest(request: request)
        } else {
            enqueueProfileRequest(apiKey: apiKey, anonymousId: anonymousId)
        }
    }

    mutating func enqueueProfileRequest(apiKey: String, anonymousId: String) {
        let payload = RequestFactory.profilePayload(
            identity: requestIdentity(apiKey: apiKey, anonymousId: anonymousId)
        )
        let updatedPayload = updateRequestAndStateWithPendingProfile(profile: payload)
        enqueueRequest(request: RequestFactory.profileRequest(apiKey: apiKey, payload: updatedPayload))
    }

    mutating func updateRequestAndStateWithPendingProfile(profile: CreateProfilePayload) -> CreateProfilePayload {
        guard let pendingProfile = pendingProfile else {
            return profile
        }
        let updatedProfile = Profile.updateProfileWithProperties(dict: pendingProfile)
        var attributes = profile.data.attributes
        mergePendingAttributes(from: updatedProfile, into: &attributes)
        attributes.location = mergedLocation(from: updatedProfile, into: attributes.location ?? .init())
        self.pendingProfile = nil

        return .init(data: .init(attributes: attributes))
    }

    /// Fills in profile attributes (name, title, organization, image, properties) from a pending
    /// profile without overwriting values already present on the request.
    private func mergePendingAttributes(
        from pending: Profile,
        into attributes: inout ProfilePayload.Attributes
    ) {
        if let firstName = pending.firstName {
            attributes.firstName = attributes.firstName ?? firstName
        }
        if let lastName = pending.lastName {
            attributes.lastName = attributes.lastName ?? lastName
        }
        if let title = pending.title {
            attributes.title = attributes.title ?? title
        }
        if let organization = pending.organization {
            attributes.organization = attributes.organization ?? organization
        }
        if let image = pending.image {
            attributes.image = attributes.image ?? image
        }
        if !pending.properties.isEmpty {
            let existing = attributes.properties.value as? [String: Any] ?? [:]
            attributes.properties = AnyCodable(
                existing.merging(pending.properties, uniquingKeysWith: { _, new in new })
            )
        }
    }

    /// Fills in location fields from a pending profile without overwriting values already present.
    private func mergedLocation(
        from pending: Profile,
        into location: ProfilePayload.Attributes.Location
    ) -> ProfilePayload.Attributes.Location {
        var location = location
        if let address1 = pending.location?.address1 {
            location.address1 = location.address1 ?? address1
        }
        if let address2 = pending.location?.address2 {
            location.address2 = location.address2 ?? address2
        }
        if let city = pending.location?.city {
            location.city = location.city ?? city
        }
        if let region = pending.location?.region {
            location.region = location.region ?? region
        }
        if let country = pending.location?.country {
            location.country = location.country ?? country
        }
        if let zip = pending.location?.zip {
            location.zip = location.zip ?? zip
        }
        if let latitude = pending.location?.latitude {
            location.latitude = location.latitude ?? latitude
        }
        if let longitude = pending.location?.longitude {
            location.longitude = location.longitude ?? longitude
        }
        return location
    }

    /// Validates the requested channels against the profile's identifiers and builds the
    /// create-subscription request. Emits a developer warning and returns `nil` when the request
    /// should not be enqueued.
    func buildSubscriptionRequest(
        apiKey: String,
        anonymousId: String,
        subscription: Subscription
    ) -> KlaviyoRequest? {
        guard let payload = buildSubscriptionPayload(anonymousId: anonymousId, subscription: subscription)
        else {
            return nil
        }
        return KlaviyoRequest(endpoint: .createSubscription(apiKey, payload))
    }

    /// Validates channels against the profile's identifiers and builds the apiKey-free
    /// `CreateSubscriptionPayload`. Emits a developer warning and returns `nil` when the request
    /// should not be enqueued. Split from `buildSubscriptionRequest` so the pre-init path can buffer it.
    func buildSubscriptionPayload(
        anonymousId: String,
        subscription: Subscription
    ) -> CreateSubscriptionPayload? {
        let channels: SubscriptionChannels?
        if let requestedChannels = subscription.channels {
            if requestedChannels.needsEmail, email == nil {
                environment.emitDeveloperWarning(
                    "Subscription requires an email for the requested channels, but email is not set."
                )
                return nil
            }
            if requestedChannels.needsPhone, phoneNumber == nil {
                environment.emitDeveloperWarning(
                    "Subscription requires a phone number for the requested channels, " +
                        "but phone number is not set."
                )
                return nil
            }

            guard let mappedChannels = SubscriptionChannels(requestedChannels) else {
                environment.emitDeveloperWarning(
                    "Subscription channels were provided but none were enabled; request was not enqueued."
                )
                return nil
            }
            channels = mappedChannels
        } else {
            // allAvailableMarketing: omit the subscriptions object so the server defaults to marketing;
            // requires at least one identifier to key channels on.
            guard email != nil || phoneNumber != nil else {
                environment.emitDeveloperWarning(
                    "Subscription requires at least one identifier the API can key channels on, " +
                        "but no identifiers are set."
                )
                return nil
            }
            channels = nil
        }

        let profile = ProfilePayload(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            subscriptions: channels,
            anonymousId: anonymousId
        )

        return CreateSubscriptionPayload(
            listId: subscription.listId,
            profile: profile,
            customSource: subscription.customSource
        )
    }
}
