//
//  NetworkSessionTests.swift
//
//
//  Created by Noah Durell on 11/18/22.
//

@testable import KlaviyoCore
import SnapshotTesting
import XCTest

@MainActor
class NetworkSessionTests: XCTestCase {
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
    }

    func testDefaultUserAgent() {
        assertSnapshot(matching: NetworkSession.defaultUserAgent, as: .dump)
    }

    func testCreateEmphemeralSesionHeaders() {
        assertSnapshot(matching: createEmphemeralSession().configuration.httpAdditionalHeaders, as: .dump)
    }

    func testSessionDataTask() async throws {
        URLProtocolOverrides.protocolClasses = [SimpleMockURLProtocol.self]
        let session = NetworkSession.production
        let sampleRequest = KlaviyoRequest(endpoint: .registerPushToken("foo", .test))
        let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 50)
        let (data, response) = try await session.data(sampleRequest.urlRequest(attemptInfo: attemptInfo))

        assertSnapshot(matching: data, as: .dump)
        assertSnapshot(matching: response, as: .dump)
    }

    func testDataTaskFallbackCancelsUnderlyingTask() async throws {
        let started = expectation(description: "request started")
        HangingURLProtocol.onStart = { started.fulfill() }
        let session = createEmphemeralSession(protocolClasses: [HangingURLProtocol.self])
        defer {
            HangingURLProtocol.onStart = nil
            session.invalidateAndCancel()
        }
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let finished = expectation(description: "request finished")
        let outcome = ResultBox()
        let task = Task {
            do {
                _ = try await NetworkSession.dataTaskFallback(session: session, request: request)
            } catch {
                outcome.error = error
            }
            finished.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)

        task.cancel()
        await fulfillment(of: [finished], timeout: 2) // a broken cancel fails here instead of hanging

        XCTAssertEqual((outcome.error as? URLError)?.code, .cancelled)
    }

    func testGetPluginConfigurationWithValidPlist() {
        // Create a temporary plist file
        let tempDir = FileManager.default.temporaryDirectory
        let plistURL = tempDir.appendingPathComponent("klaviyo-plugin-configuration.plist")

        // Create plist content
        let plistContent: [String: Any] = [
            "klaviyo_sdk_plugin_name_override": "test-plugin",
            "klaviyo_sdk_plugin_version_override": "1.0.0"
        ]

        do {
            // Write plist to temporary location
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: plistContent,
                format: .xml,
                options: 0
            )
            try plistData.write(to: plistURL)
            // Create a mock bundle that returns our temporary plist
            let mockBundle = MockBundle(plistURL: plistURL)

            // Call the function with our mock bundle
            let result = NetworkSession.defaultUserAgent(bundle: mockBundle)

            // Verify the result
            XCTAssertNotNil(result)
            XCTAssertEqual(result, "FooApp/1.2.3 (com.klaviyo.fooapp; build:1; iOS 1.1.1) klaviyo-swift/5.7.0 (test-plugin/1.0.0)")

            // Clean up
            try FileManager.default.removeItem(at: plistURL)
        } catch {
            XCTFail("Failed to create test plist: \(error)")
        }
    }

    func testGetPluginConfigurationWithMissingPlist() {
        // Create a mock bundle that returns nil for the plist URL
        let mockBundle = MockBundle(plistURL: nil)

        // Call the function with our mock bundle
        let result = NetworkSession.defaultUserAgent(bundle: mockBundle)

        XCTAssertEqual(result, "FooApp/1.2.3 (com.klaviyo.fooapp; build:1; iOS 1.1.1) klaviyo-swift/5.7.0")
    }

    func testGetPluginConfigurationWithInvalidPlist() {
        // Create a temporary plist file with invalid content
        let tempDir = FileManager.default.temporaryDirectory
        let plistURL = tempDir.appendingPathComponent("klaviyo-plugin-configuration.plist")

        do {
            // Write invalid data to the plist
            let invalidData = "invalid plist data".data(using: .utf8)!
            try invalidData.write(to: plistURL)

            // Create a mock bundle that returns our temporary plist
            let mockBundle = MockBundle(plistURL: plistURL)

            // Call the function with our mock bundle
            let result = NetworkSession.defaultUserAgent(bundle: mockBundle)

            // Verify the result is default
            XCTAssertEqual(result, "FooApp/1.2.3 (com.klaviyo.fooapp; build:1; iOS 1.1.1) klaviyo-swift/5.7.0")

            // Clean up
            try FileManager.default.removeItem(at: plistURL)
        } catch {
            XCTFail("Failed to create test plist: \(error)")
        }
    }
}

// Mock Bundle class for testing
private class MockBundle: Bundle {
    private let mockPlistURL: URL?

    init(plistURL: URL?) {
        mockPlistURL = plistURL
        super.init()
    }

    override func url(forResource name: String?, withExtension ext: String?) -> URL? {
        if name == "klaviyo-plugin-configuration" && ext == "plist" {
            return mockPlistURL
        }
        return nil
    }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _error: Error?
    var error: Error? {
        get { lock.lock(); defer { lock.unlock() }; return _error }
        set { lock.lock(); _error = newValue; lock.unlock() }
    }
}

private final class HangingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _onStart: (() -> Void)?
    static var onStart: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onStart }
        set { lock.lock(); _onStart = newValue; lock.unlock() }
    }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.onStart?() }
    override func stopLoading() {}
}
