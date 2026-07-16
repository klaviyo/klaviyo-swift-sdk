//
//  KlaviyoSwiftEnvironment.swift
//
//
//  Created by Ajay Subramanya on 8/8/24.
//

import Combine
import Foundation
import KlaviyoCore

var klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.production

struct KlaviyoSwiftEnvironment {
    var send: (KlaviyoAction) -> Task<Void, Never>?
    var state: () -> KlaviyoState
    var statePublisher: () -> AnyPublisher<KlaviyoState, Never>
    var stateChangePublisher: () -> AnyPublisher<KlaviyoAction, Never>
    var pruneCategory: (String) -> Void

    static let production: KlaviyoSwiftEnvironment = {
        let store = Store.production

        return KlaviyoSwiftEnvironment(
            send: { action in
                store.send(action)
            },
            state: { store.state.value },
            statePublisher: { store.state.eraseToAnyPublisher() },
            stateChangePublisher: StateChangePublisher().publisher,
            pruneCategory: { categoryIdentifier in
                KlaviyoCategoryManager.shared.pruneCategory(categoryIdentifier: categoryIdentifier)
            }
        )
    }()
}
