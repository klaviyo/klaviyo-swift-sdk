//
//  FileUtilsTests.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/29/22.
//

@testable import KlaviyoCore
import XCTest

class FileUtilsTests: XCTestCase {
    var dataToWrite: Data?
    var wroteToFile = false
    var removedFile = false

    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        environment.fileClient.write = { [weak self] data, _ in
            self?.wroteToFile = true
            self?.dataToWrite = data
        }
        environment.fileClient.removeItem = { [weak self] _ in
            self?.removedFile = true
        }
    }

    override func tearDownWithError() throws {
        wroteToFile = false
        dataToWrite = nil
        removedFile = false
    }

    func testFilePathForData() throws {
        let eventsResult = filePathForData(apiKey: "mykey", data: "events")
        XCTAssertEqual(URL(string: "fake_url/klaviyo-mykey-events.plist")!, eventsResult)

        let peopleResult = filePathForData(apiKey: "mykey", data: "people")
        XCTAssertEqual(URL(string: "fake_url/klaviyo-mykey-people.plist")!, peopleResult)
    }

    func testRemoveItemWithError() {
        environment.fileClient.removeItem = { _ in
            throw FakeFileError.fake
        }
        XCTAssertFalse(removeFile(at: TEST_URL))
    }

    // MARK: - loadPlist Tests

    func testLoadPlist_ReturnsNilForNonExistentPlistInMainBundle() {
        XCTAssertNil(loadPlist(named: "non-existent-plist"))
    }

    func testLoadPlist_ReturnsNilForNonExistentPlistInExplicitBundle() throws {
        let bundle = try makeTempBundle(named: "empty-bundle")
        XCTAssertNil(loadPlist(named: "non-existent-plist", in: bundle))
    }

    func testLoadPlist_ReturnsDictionaryFromExplicitBundle() throws {
        let bundle = try makeTempBundle(
            named: "test-wrapper-sdk",
            plistName: "klaviyo-sdk-configuration",
            plistContents: ["klaviyo_sdk_name": "klaviyo-react-native-sdk", "klaviyo_sdk_version": "3.0.0"]
        )

        let result = loadPlist(named: "klaviyo-sdk-configuration", in: bundle)

        XCTAssertEqual(result?["klaviyo_sdk_name"] as? String, "klaviyo-react-native-sdk")
        XCTAssertEqual(result?["klaviyo_sdk_version"] as? String, "3.0.0")
    }

    // MARK: - wrapperSDKConfig path coverage (paths 3 & 4)

    //
    // Paths 1 & 2 rely on Bundle.main and cannot be exercised in isolation in a unit test.
    // The tests below verify the loadPlist(named:in:) mechanism used by all four paths,
    // covering the dynamic-framework cases (paths 3 & 4) directly.

    /// Path 3: s.resources + use_frameworks! dynamic
    /// CocoaPods copies resources flat into the .framework bundle — the plist is at its root.
    func testLoadPlist_LoadsFromFrameworkBundleRoot() throws {
        let frameworkBundle = try makeTempBundle(
            named: "klaviyo-react-native-sdk.framework",
            plistName: "klaviyo-sdk-configuration",
            plistContents: ["klaviyo_sdk_name": "klaviyo-react-native-sdk", "klaviyo_sdk_version": "2.1.0"]
        )

        let result = loadPlist(named: "klaviyo-sdk-configuration", in: frameworkBundle)

        XCTAssertEqual(result?["klaviyo_sdk_name"] as? String, "klaviyo-react-native-sdk")
        XCTAssertEqual(result?["klaviyo_sdk_version"] as? String, "2.1.0")
    }

    /// Path 4: s.resource_bundles + use_frameworks! dynamic
    /// CocoaPods places a named .bundle inside the .framework — the plist lives in that nested bundle.
    func testLoadPlist_LoadsFromNestedBundleInsideFramework() throws {
        let nestedBundle = try makeTempBundle(
            named: "klaviyo-react-native-sdk.bundle",
            plistName: "klaviyo-sdk-configuration",
            plistContents: ["klaviyo_sdk_name": "klaviyo-react-native-sdk", "klaviyo_sdk_version": "2.2.0"]
        )

        let result = loadPlist(named: "klaviyo-sdk-configuration", in: nestedBundle)

        XCTAssertEqual(result?["klaviyo_sdk_name"] as? String, "klaviyo-react-native-sdk")
        XCTAssertEqual(result?["klaviyo_sdk_version"] as? String, "2.2.0")
    }

    // MARK: - CocoaPods framework directory naming

    // CocoaPods replaces hyphens with underscores in framework/module directory names (C99 identifiers
    // cannot contain hyphens). Paths 3 & 4 of wrapperSDKConfig must use the underscore form when
    // constructing .framework paths, or Bundle(url:) will return nil and the wrapper goes undetected.

    func testFrameworkDirectoryNamesHaveNoHyphens() {
        for bundleName in KlaviyoEnvironment.knownWrapperBundleNames {
            let frameworkDirName = bundleName.replacingOccurrences(of: "-", with: "_")
            XCTAssertFalse(
                frameworkDirName.contains("-"),
                "Framework directory name '\(frameworkDirName)' derived from '\(bundleName)' must not contain hyphens"
            )
        }
    }

    func testKnownBundleNamesProduceExpectedFrameworkDirectoryNames() {
        let expected: [String: String] = [
            "klaviyo-react-native-sdk": "klaviyo_react_native_sdk",
            "klaviyo_flutter_sdk": "klaviyo_flutter_sdk"
        ]

        for bundleName in KlaviyoEnvironment.knownWrapperBundleNames {
            let frameworkDirName = bundleName.replacingOccurrences(of: "-", with: "_")
            XCTAssertEqual(
                frameworkDirName,
                expected[bundleName],
                "Unexpected framework directory name for bundle '\(bundleName)'"
            )
        }
    }

    // MARK: - Performance regression guard

    /// Guards against re-introducing a Bundle.allBundles scan, which caused a 3+ second hang.
    /// Verifies the main-bundle-only path (path 1) completes in well under 100ms.
    func testLoadPlist_MainBundleLookupIsNotSlow() {
        let start = Date()
        _ = loadPlist(named: "klaviyo-sdk-configuration")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.1, "loadPlist took \(elapsed)s — possible bundle scan regression")
    }

    // MARK: - Helpers

    /// Creates a minimal on-disk bundle directory in a temp folder, optionally containing a plist.
    @discardableResult
    private func makeTempBundle(
        named name: String,
        plistName: String? = nil,
        plistContents: [String: String] = [:]
    ) throws -> Bundle {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let bundleURL = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        if let plistName {
            let plistURL = bundleURL.appendingPathComponent("\(plistName).plist")
            (plistContents as NSDictionary).write(to: plistURL, atomically: true)
        }

        guard let bundle = Bundle(url: bundleURL) else {
            throw XCTestError(.failureWhileWaiting, userInfo: [NSLocalizedDescriptionKey: "Could not create Bundle at \(bundleURL.path)"])
        }
        return bundle
    }
}
