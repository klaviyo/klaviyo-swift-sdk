//
//  SimpleMockURLProtocol.swift
//
//
//  Created by Noah Durell on 11/21/22.
//

import Foundation

open class SimpleMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    open override func startLoading() {
        self.client?.urlProtocol(self, didReceive: .validResponse, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: Data())
        self.client?.urlProtocolDidFinishLoading(self)
    }
    
    open override func stopLoading() {
        
    }
    
    open override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    open override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
}
