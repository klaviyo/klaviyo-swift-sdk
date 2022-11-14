//
//  SimpleMockURLProtocol.swift
//  
//
//  Created by Noah Durell on 11/21/22.
//

import Foundation

open class SimpleMockURLProtocol: URLProtocol {
    open override func startLoading() {
        self.client?.urlProtocolDidFinishLoading(self)
    }
    
    open override func stopLoading() {
        
    }
    
    open override class func canInit(with task: URLSessionTask) -> Bool {
        return true
    }
    
    open override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
}
