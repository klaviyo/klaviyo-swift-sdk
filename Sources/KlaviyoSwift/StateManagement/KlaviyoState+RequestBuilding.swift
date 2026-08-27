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
    private mutating func resolveProfileConsumingPending() -> Profile {
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
            profile: ProfilePayload(resolveProfileConsumingPending(), anonymousId: anonymousId)
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
        var attributes = profile.data.attributes
        var location = profile.data.attributes.location ?? .init()
        let properties = profile.data.attributes.properties.value as? [String: Any] ?? [:]
        let updatedProfile = Profile.updateProfileWithProperties(dict: pendingProfile)

        if let firstName = updatedProfile.firstName {
            attributes.firstName = attributes.firstName ?? firstName
        }
        if let lastName = updatedProfile.lastName {
            attributes.lastName = attributes.lastName ?? lastName
        }
        if let title = updatedProfile.title {
            attributes.title = attributes.title ?? title
        }
        if let organization = updatedProfile.organization {
            attributes.organization = attributes.organization ?? organization
        }
        if !updatedProfile.properties.isEmpty {
            attributes.properties = AnyCodable(
                properties.merging(updatedProfile.properties, uniquingKeysWith: { _, new in new })
            )
        }

        if let address1 = updatedProfile.location?.address1 {
            location.address1 = location.address1 ?? address1
        }
        if let address2 = updatedProfile.location?.address2 {
            location.address2 = location.address2 ?? address2
        }
        if let city = updatedProfile.location?.city {
            location.city = location.city ?? city
        }
        if let region = updatedProfile.location?.region {
            location.region = location.region ?? region
        }
        if let country = updatedProfile.location?.country {
            location.country = location.country ?? country
        }
        if let zip = updatedProfile.location?.zip {
            location.zip = location.zip ?? zip
        }
        if let image = updatedProfile.image {
            attributes.image = attributes.image ?? image
        }
        if let latitude = updatedProfile.location?.latitude {
            location.latitude = location.latitude ?? latitude
        }
        if let longitude = updatedProfile.location?.longitude {
            location.longitude = location.longitude ?? longitude
        }

        attributes.location = location
        self.pendingProfile = nil

        return .init(data: .init(attributes: attributes))
    }

    /// Validates the requested channels against the profile's identifiers and builds the create-subscription
    /// request. Emits a developer warning and returns `nil` when the request should not be enqueued.
    func buildSubscriptionRequest(
        apiKey: String,
        anonymousId: String,
        subscription: Subscription
    ) -> KlaviyoRequest? {
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

        let payload = CreateSubscriptionPayload(
            listId: subscription.listId,
            profile: profile,
            customSource: subscription.customSource
        )

        let endpoint = KlaviyoEndpoint.createSubscription(apiKey, payload)
        return KlaviyoRequest(endpoint: endpoint)
    }
}
