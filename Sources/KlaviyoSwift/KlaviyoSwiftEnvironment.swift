//
//  KlaviyoSwiftEnvironment.swift
//
//
//  Created by Ajay Subramanya on 8/8/24.
//

import Combine
import Foundation

var klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.production

struct KlaviyoSwiftEnvironment {
    var send: (KlaviyoAction) -> Task<Void, Never>?
    var state: () -> KlaviyoState
    var statePublisher: () -> AnyPublisher<KlaviyoState, Never>

    static let production: KlaviyoSwiftEnvironment = {
        let store = Store.production

        return KlaviyoSwiftEnvironment(
            send: { action in
                store.send(action)
            },
            state: { store.state.value },
            statePublisher: { store.state.eraseToAnyPublisher() })
    }()
}
