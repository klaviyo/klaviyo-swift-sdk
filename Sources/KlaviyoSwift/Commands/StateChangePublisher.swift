//
//  StateChangePublisher.swift
//
//
//  Created by Noah Durell on 12/21/22.
//

import Combine
import Foundation
import KlaviyoCore

@_spi(KlaviyoPrivate)
public enum StateChangePublisher {
    /// Assembles the private state feed from the canonical Core publishers (identity + token) gated
    /// on the SDK having reached `.initialized`.
    private static func createStatePublisher() -> AnyPublisher<PrivateState, Never> {
        Publishers.CombineLatest3(
            IdentityStore.shared.publisher,
            IdentityStore.shared.tokenPublisher,
            LifecycleState.shared.publisher
        )
        .filter { $0.2 == .initialized }
        .map { profile, token, _ in
            PrivateState(
                email: profile.email,
                anonymousId: profile.anonymousId,
                phoneNumber: profile.phoneNumber,
                externalId: profile.externalId,
                pushToken: token?.pushToken
            )
        }
        .removeDuplicates()
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    @_spi(KlaviyoPrivate)
    public struct PrivateState: Equatable {
        public var email: String?
        public var anonymousId: String?
        public var phoneNumber: String?
        public var externalId: String?
        public var pushToken: String?
    }

    @_spi(KlaviyoPrivate)
    public static func internalStatePublisher() -> AnyPublisher<PrivateState, Never> {
        createStatePublisher()
    }
}
