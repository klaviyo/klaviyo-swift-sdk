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
@MainActor
public struct StateChangePublisher: Sendable {
    static var debouncedPublisher: (AnyPublisher<KlaviyoState, Never>) -> AnyPublisher<KlaviyoState, Never> = { publisher in
        publisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.global())
            .eraseToAnyPublisher()
    }

    private static func createStatePublisher() -> AnyPublisher<KlaviyoState, Never> {
        klaviyoSwiftEnvironment.statePublisher()
            .filter { state in state.initalizationState == .initialized }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var publisher: @MainActor () -> AsyncStream<KlaviyoState> = {
        AsyncStream { continuation in
            Task {
                for await state in debouncedPublisher(createStatePublisher()).values {
                    continuation.yield(state)
                }
            }
        }
    }

    @_spi(KlaviyoPrivate)
    public struct PrivateState: Sendable {
        public var email: String?
        public var anonymousId: String?
        public var phoneNumber: String?
        public var externalId: String?
        public var pushToken: String?
    }

    @_spi(KlaviyoPrivate)
    @MainActor
    public static func internalStatePublisher() -> AsyncStream<PrivateState> {
        let publisher = StateChangePublisher.createStatePublisher()
        return AsyncStream { continuation in
            Task {
                for await state in publisher
                    .subscribe(on: DispatchQueue.main).values {
                    continuation.yield(PrivateState(
                        email: state.email,
                        anonymousId: state.anonymousId,
                        phoneNumber: state.phoneNumber,
                        externalId: state.externalId,
                        pushToken: state.pushTokenData?.pushToken))
                }
            }
        }
    }
}
