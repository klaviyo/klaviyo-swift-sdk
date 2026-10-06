//
//  IAFWebViewModelScriptEscapingTests.swift
//  klaviyo-swift-sdk
//
//  Checks that profile and auth token values reach the page unchanged whatever
//  characters they contain, on a page that is loading and on a live page. The scripts
//  the view model generates run in JavaScriptCore against a stub `document.head`.
//

@testable import KlaviyoCore
@testable import KlaviyoForms
import JavaScriptCore
import XCTest

@MainActor
final class IAFWebViewModelScriptEscapingTests: XCTestCase {
    private static let profileAttribute = "data-klaviyo-profile"
    private static let jwtAttribute = "data-klaviyo-jwt"

    private let testValues = [
        "ordinary@example.com",
        "o'brien@example.com",
        "say \"hi\"@example.com",
        #"back\slash@example.com"#,
        "line\nbreak@example.com",
        "ünï©ode😀@example.com",
        "separator\u{2028}\u{2029}@example.com",
        "</script>@example.com"
    ]

    override func setUp() async throws {
        try await super.setUp()
        seedCoreStores()
    }

    override func tearDown() async throws {
        IdentityStore.shared.reset()
        try await super.tearDown()
    }

    func testLoadScriptSetsProfileAndTokenUnchanged() throws {
        for value in testValues {
            let profile = makeProfile(value)
            let page = try runLoadScript(profile: profile, token: value)

            try assertAttributes(of: page, profile: profile, token: value, value)
        }
    }

    func testLoadScriptSetsProfileBeforeToken() throws {
        for value in testValues {
            let page = try runLoadScript(profile: makeProfile(value), token: value)

            XCTAssertEqual(
                page.operations.map(\.name),
                [Self.profileAttribute, Self.jwtAttribute],
                value
            )
            XCTAssertTrue(page.operations.allSatisfy { $0.kind == "set" }, value)
        }
    }

    func testLoadScriptWithoutTokenWritesNoJwt() throws {
        for value in testValues {
            let profile = makeProfile(value)
            let page = try runLoadScript(profile: profile, token: nil)

            XCTAssertEqual(page.operations.map(\.name), [Self.profileAttribute], value)
            XCTAssertNil(page.attributes[Self.jwtAttribute], value)
            XCTAssertEqual(
                try jsonObject(page.attributes[Self.profileAttribute]),
                try jsonObject(profile.toHtmlString()),
                value
            )
        }
    }

    func testLivePageWritesSetProfileAndTokenUnchanged() async throws {
        let authTokenManager = makeUnboundedAuthTokenManager()
        for value in testValues {
            let profile = makeProfile(value)
            IdentityStore.shared.update(profile)
            let viewModel = try IAFWebViewModel(
                url: XCTUnwrap(URL(string: "https://example.com")),
                apiKey: "abc123",
                profileData: nil,
                authTokenManager: authTokenManager
            )
            let delegate = MockIAFWebViewDelegate(viewModel: viewModel)
            viewModel.delegate = delegate

            await delegate.awaitScript(containing: Self.profileAttribute)
            let cached = try await cacheTestToken(subject: value, in: authTokenManager)
            await viewModel.pushAuthToken(cached.token, generation: cached.generation)
            let page = try JavaScriptPage()
            for script in delegate.evaluatedScripts {
                try page.run(script)
            }

            try assertAttributes(of: page, profile: profile, token: cached.token, value)
            IdentityStore.shared.reset()
        }
    }

    // MARK: - Helpers

    private func makeProfile(_ value: String) -> ProfileData {
        ProfileData(email: value, phoneNumber: value, externalId: value, anonymousId: "anon")
    }

    private func runLoadScript(profile: ProfileData, token: String?) throws -> JavaScriptPage {
        let viewModel = IAFWebViewModel(
            url: URL(string: "https://example.com")!,
            apiKey: "abc123",
            profileData: profile,
            authToken: token
        )
        let source = try XCTUnwrap(
            viewModel.loadScripts?.map(\.source).first { $0.contains(Self.profileAttribute) }
        )
        let page = try JavaScriptPage()
        try page.run(source)
        return page
    }

    private func assertAttributes(
        of page: JavaScriptPage,
        profile: ProfileData,
        token: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            try jsonObject(page.attributes[Self.profileAttribute]),
            try jsonObject(profile.toHtmlString()),
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(page.attributes[Self.jwtAttribute], token, message, file: file, line: line)
    }

    private func jsonObject(_ json: String?) throws -> NSDictionary {
        let data = try Data(XCTUnwrap(json).utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}

/// A JavaScriptCore context whose `document.head` records every attribute write and removal.
private final class JavaScriptPage {
    struct Operation {
        let kind: String
        let name: String
    }

    private struct ScriptFailure: Error, CustomStringConvertible {
        let description: String
    }

    private let context: JSContext
    private var exceptions: [String] = []

    init() throws {
        let context = try XCTUnwrap(JSContext())
        self.context = context
        context.exceptionHandler = { [weak self] _, exception in
            self?.exceptions.append(exception?.toString() ?? "unknown exception")
        }
        context.evaluateScript(
            """
            var __log = [];
            var __attributes = {};
            var document = { head: {
                setAttribute: function(name, value) {
                    __log.push({ kind: 'set', name: name });
                    __attributes[name] = value;
                },
                removeAttribute: function(name) {
                    __log.push({ kind: 'remove', name: name });
                    delete __attributes[name];
                }
            } };
            """
        )
        XCTAssertTrue(exceptions.isEmpty, "\(exceptions)")
    }

    func run(_ script: String) throws {
        context.evaluateScript(script)
        if let failure = exceptions.first {
            throw ScriptFailure(description: "\(failure): \(script.debugDescription)")
        }
    }

    var attributes: [String: String] {
        let object = context.evaluateScript("__attributes")?.toDictionary() as? [String: String]
        return object ?? [:]
    }

    var operations: [Operation] {
        let entries = context.evaluateScript("__log")?.toArray() as? [[String: String]] ?? []
        return entries.compactMap { entry in
            guard let kind = entry["kind"], let name = entry["name"] else { return nil }
            return Operation(kind: kind, name: name)
        }
    }
}
