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
public enum StateChangePublisher {
    private static func createStatePublisher() -> AnyPublisher<KlaviyoState, Never> {
        klaviyoSwiftEnvironment.statePublisher()
            .filter { state in state.initalizationState == .initialized }
            .removeDuplicates()
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
                PrivateState(
                    email: state.email,
                    anonymousId: state.anonymousId,
                    phoneNumber: state.phoneNumber,
                    externalId: state.externalId,
                    pushToken: state.pushTokenData?.pushToken
                )
            }
            .eraseToAnyPublisher()
    }
}
