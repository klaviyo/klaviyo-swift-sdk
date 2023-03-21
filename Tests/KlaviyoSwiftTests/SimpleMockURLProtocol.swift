//
//  SimpleMockURLProtocol.swift
//
//
//  Created by Noah Durell on 11/21/22.
//

import Foundation

open class SimpleMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override open func startLoading() {
        client?.urlProtocol(self, didReceive: .validResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override open func stopLoading() {}

    override open class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override open class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
}
