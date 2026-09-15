//
//  RequestBuilding.swift
//
//
//  Created by Isobelle Lim on 9/14/26.
//

import Foundation
import KlaviyoCore

// MARK: - Pure request-builder free functions

/// Builds a `RequestIdentity` from the given identity, apiKey, and anonymousId.
/// Pure equivalent of `KlaviyoState.requestIdentity(apiKey:anonymousId:)` — reads from
/// an explicit `ProfileData` instead of `self`.
func requestIdentity(_ identity: ProfileData, apiKey: String, anonymousId: String) -> RequestIdentity {
    RequestIdentity(
        apiKey: apiKey,
        anonymousId: anonymousId,
        email: identity.email,
        phoneNumber: identity.phoneNumber,
        externalId: identity.externalId
    )
}

/// Builds a `ProfilePayload` from the incoming profile, overriding its identifiers with
/// the canonical values from `identity`. Pure equivalent of
/// `KlaviyoState.profilePayload(from:anonymousId:)`.
func profilePayload(from profile: Profile, identity: ProfileData, anonymousId: String) -> ProfilePayload {
    ProfilePayload(
        profile,
        email: identity.email,
        phoneNumber: identity.phoneNumber,
        externalId: identity.externalId,
        anonymousId: anonymousId
    )
}

/// Builds a push-token registration request from the given identity. Pure equivalent of
/// `KlaviyoState.resolvedTokenRequest(apiKey:anonymousId:pushToken:enablement:)`.
func resolvedTokenRequest(
    identity: ProfileData,
    apiKey: String,
    anonymousId: String,
    pushToken: String,
    enablement: PushEnablement
) -> KlaviyoRequest {
    let identityProfile = Profile(
        email: identity.email,
        phoneNumber: identity.phoneNumber,
        externalId: identity.externalId
    )
    return RequestFactory.tokenRequest(
        apiKey: apiKey,
        pushToken: pushToken,
        enablement: enablement,
        background: environment.getBackgroundSetting().rawValue,
        profile: ProfilePayload(identityProfile, anonymousId: anonymousId)
    )
}

/// Validates the requested channels against the profile's identifiers and builds the
/// `CreateSubscriptionPayload`. Emits a developer warning and returns `nil` when the request
/// should not be enqueued. Pure equivalent of
/// `KlaviyoState.buildSubscriptionPayload(anonymousId:subscription:)`.
func buildSubscriptionPayload(
    identity: ProfileData,
    anonymousId: String,
    subscription: Subscription
) -> CreateSubscriptionPayload? {
    let channels: SubscriptionChannels?
    if let requestedChannels = subscription.channels {
        if requestedChannels.needsEmail, identity.email == nil {
            environment.emitDeveloperWarning(
                "Subscription requires an email for the requested channels, but email is not set."
            )
            return nil
        }
        if requestedChannels.needsPhone, identity.phoneNumber == nil {
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
        guard identity.email != nil || identity.phoneNumber != nil else {
            environment.emitDeveloperWarning(
                "Subscription requires at least one identifier the API can key channels on, " +
                    "but no identifiers are set."
            )
            return nil
        }
        channels = nil
    }

    let profile = ProfilePayload(
        email: identity.email,
        phoneNumber: identity.phoneNumber,
        externalId: identity.externalId,
        subscriptions: channels,
        anonymousId: anonymousId
    )

    return CreateSubscriptionPayload(
        listId: subscription.listId,
        profile: profile,
        customSource: subscription.customSource
    )
}
