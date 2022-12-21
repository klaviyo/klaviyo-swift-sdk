//
//  StateChangePublisher.swift
//  
//
//  Created by Noah Durell on 12/21/22.
//

import Foundation
import Combine
import UIKit

let DEBOUNCE_INTERVAL = DispatchQueue.SchedulerTimeType.Stride.seconds(1.0)

public struct StateChangePublisher {
    
    static var debouncedPublisher: (AnyPublisher<KlaviyoState, Never>) -> AnyPublisher<KlaviyoState, Never> = { publisher in
        publisher
            .debounce(for: DEBOUNCE_INTERVAL, scheduler: DispatchQueue.global())
            .eraseToAnyPublisher()
    }
    
    // publisher to listen for state and persist them on an interval.
    // does not emit action but mapped that way so it can be used in the store.
    var publisher: () -> AnyPublisher<KlaviyoAction, Never> = {
        let statePublisher = environment.analytics.store.state
            .removeDuplicates()
            .filter { state in state.initalizationState != .initialized }
            .eraseToAnyPublisher()
        return debouncedPublisher(statePublisher)
            .handleEvents(receiveOutput: { state in
                saveKlaviyoState(state: state)
            })
            .flatMap { _ in Empty<KlaviyoAction, Never>() }
            .eraseToAnyPublisher()
    }
}
