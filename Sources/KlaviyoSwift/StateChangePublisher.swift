//
//  StateChangePublisher.swift
//  
//
//  Created by Noah Durell on 12/21/22.
//

import Foundation
import Combine
import UIKit

public struct StateChangePublisher {
    
    static var debouncedPublisher: (AnyPublisher<KlaviyoState, Never>) -> AnyPublisher<KlaviyoState, Never> = { publisher in
        publisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.global())
            .eraseToAnyPublisher()
    }
    
    // publisher to listen for state and persist them on an interval.
    // does not emit action but mapped that way so it can be used in the store.
    var publisher: () -> AnyPublisher<KlaviyoAction, Never> = {
        let statePublisher = environment.analytics.store.state
            .filter { state in state.initalizationState == .initialized }
            .removeDuplicates()
            .eraseToAnyPublisher()
        return debouncedPublisher(statePublisher)
            .flatMap { state in
                saveKlaviyoState(state: state)
                return Empty<KlaviyoAction, Never>()
            }
            .eraseToAnyPublisher()
    }
}
