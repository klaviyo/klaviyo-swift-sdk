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
        guard let apiKey,
              let anonymousId else {
            environment.emitDeveloperWarning("SDK internal error")
            return
        }
        // if we have push data and we are switching emails
        // we want to associate the token with the new email.
        if let pushTokenData {
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
        guard let pendingProfile else {
            return profile
        }
        let updatedProfile = Profile.updateProfileWithProperties(dict: pendingProfile)
        var attributes = profile.data.attributes
        PendingProfileFold.mergePendingAttributes(from: updatedProfile, into: &attributes)
        attributes.location = PendingProfileFold.mergedLocation(
            from: updatedProfile, into: attributes.location ?? .init()
        )
        self.pendingProfile = nil

        return .init(data: .init(attributes: attributes))
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
