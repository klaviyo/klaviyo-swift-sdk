//
//  KlaviyoStateTests.swift
//  
//
//  Created by Noah Durell on 12/1/22.
//

import Foundation
import XCTest
@testable import KlaviyoSwift
import SnapshotTesting



final class KlaviyoStateTests: XCTestCase {
    
    let TEST_EVENT = [
        "event": "$opened_push",
        "properties": [
            "prop1": "propValue"
        ],
        "customer_properties": [
            "foo": "bar"
        ]
    ] as [String : Any]

    let TEST_PROFILE = [
        "properties": [
            "foo2": "bar2"
        ]
    ]
    
    let TEST_INVALID_EVENT = [
        "properties": [
            "prop1": "propValue"
        ],
        "customer_properties": [
            "foo": "bar"
        ]
    ]
    let TEST_INVALID_PROFILE = [
        "garbage_key": [
            "foo": "bar"
        ]
    ]
    let TEST_INVALID_PROPERTIES_EVENT = [
        "properties": [
            1: "propValue"
        ],
        "customer_properties": [
            "foo": "bar"
        ]
    ]

    let TEST_INVALID_CUSTOMER_PROPERTIES_EVENT = [
        "event": "$opened_push",
        "properties": [
            "fo": "propValue"
        ],
        "customer_properties": [
            1: "bar"
        ]
    ] as [String : Any]
    let TEST_INVALID_PROPERTIES_PROFILE = [
        "event": "$opened_push",
        "properties": [
            1: "propValue"
        ],
    ] as [String : Any]
    
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }
    
    func testLoadNewKlaviyoState() throws {
        environment.fileClient.fileExists = { _ in false }
        environment.archiverClient.unarchivedMutableArray = { _ in [] }
        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }
    
    func testLoadWithRequestMigration() throws {
        var firstCall = true
        environment.fileClient.fileExists = { _ in
            if firstCall {
                firstCall = false
                return false
            }
            return true
            
        }
        var firstUnarchiveCall = true
        environment.archiverClient.unarchivedMutableArray = { _ in
            if firstUnarchiveCall {
                firstUnarchiveCall = false
                return [self.TEST_EVENT]
            } else {
                return [self.TEST_PROFILE]
            }
        }
        var removeCounter = 0
        environment.fileClient.removeItem = { _ in removeCounter += 1 }
        
        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
        XCTAssertEqual(removeCounter, 2)
    }
    
    func testMigrateInvalidDataSkipped() throws {
        var firstCall = true
        environment.fileClient.fileExists = { _ in
            if firstCall {
                firstCall = false
                return false
            }
            return true
            
        }
        var firstUnarchiveCall = true
        environment.archiverClient.unarchivedMutableArray = { _ in
            if firstUnarchiveCall {
                firstUnarchiveCall = false
                return [self.TEST_INVALID_EVENT]
            }
            return [self.TEST_INVALID_PROFILE]
        }
        
        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }
    
    func testInvalidEventPropertiesOnData() throws {
        var firstCall = true
        environment.fileClient.fileExists = { _ in
            if firstCall {
                firstCall = false
                return false
            }
            return true
            
        }
        var firstUnarchiveCall = true
        environment.archiverClient.unarchivedMutableArray = { _ in
            if firstUnarchiveCall {
                firstUnarchiveCall = false
                return [self.TEST_INVALID_PROPERTIES_EVENT, self.TEST_INVALID_CUSTOMER_PROPERTIES_EVENT]
            }
            return [self.TEST_INVALID_PROPERTIES_PROFILE]
        }
        
        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }

    func testStateFileExistsInvalidData() throws {
        environment.fileClient.fileExists = { _ in
            return true
            
        }
        environment.data = { _ in
            throw NSError(domain: "missing file", code: 1)
        }
        environment.archiverClient.unarchivedMutableArray = { _ in
            XCTFail("unarchivedMutableArray should not be called.")
            return []
        }
        
        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }
    
    func testStateFileExistsInvalidJSON() throws {
        environment.fileClient.fileExists = { _ in
            return true
            
        }
        
        environment.analytics.decoder = DataDecoder(jsonDecoder: InvalidJSONDecoder())
        environment.archiverClient.unarchivedMutableArray = { _ in
            XCTFail("unarchivedMutableArray should not be called.")
            return []
        }
        
        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }
    
    func testValidStateFileExists() throws {
        environment.fileClient.fileExists = { _ in
            return true
            
        }
        environment.data = { _ in
            return try! JSONEncoder().encode(KlaviyoState(apiKey: "foo", anonymousId: environment.analytics.uuid().uuidString, queue: [], requestsInFlight: []))
        }
        environment.analytics.decoder = DataDecoder(jsonDecoder: decoder)
        
        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }
}
