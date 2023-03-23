//
//  StateChangePublisher.swift
//
//
//  Created by Noah Durell on 12/21/22.
//

import Combine
import Foundation
import UIKit

@_spi(KlaviyoPrivate)
public struct StateChangePublisher {
    static var debouncedPublisher: (AnyPublisher<KlaviyoState, Never>) -> AnyPublisher<KlaviyoState, Never> = { publisher in
        publisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.global())
            .eraseToAnyPublisher()
    }

    private static func createStatePublisher() -> AnyPublisher<KlaviyoState, Never> {
        environment.analytics.statePublisher()
            .filter { state in state.initalizationState == .initialized }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // publisher to listen for state and persist them on an interval.
    // does not emit action but mapped that way so it can be used in the store.
    var publisher: () -> AnyPublisher<KlaviyoAction, Never> = {
        debouncedPublisher(createStatePublisher())
            .flatMap { state -> Empty<KlaviyoAction, Never> in
                saveKlaviyoState(state: state)
                return Empty<KlaviyoAction, Never>()
            }
            .eraseToAnyPublisher()
    }

    @_spi(KlaviyoPrivate)
    public struct PrivateState {
        public var email: String?
        public var anonymousId: String?
        public var phoneNumber: String?
        public var externalId: String?
        public var pushToken: String?
    }

    @_spi(KlaviyoPrivate)
    public static func internalStatePublisher() -> AnyPublisher<PrivateState, Never> {
        createStatePublisher()
            .map { state in
                PrivateState(email: state.email, anonymousId: state.anonymousId, phoneNumber: state.phoneNumber, externalId: state.externalId, pushToken: state.pushToken)
            }
            .eraseToAnyPublisher()
    }
}
