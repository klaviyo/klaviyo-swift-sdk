//
//  StateChangePublisherTests.swift
//  
//
//  Created by Noah Durell on 12/21/22.
//

import Foundation
import XCTest
@testable import KlaviyoSwift

final class StateChangePublisherTests: XCTestCase {
    
    func testReducer( state: inout KlaviyoState, action: KlaviyoAction) -> EffectTask<KlaviyoAction> {
        return .none
    }

    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testStateChangePublisher() throws {
        
        //environment.analytics.store = Store(initialState: KlaviyoState(), reducer: <#T##ReducerProtocol#>)
    }

}
