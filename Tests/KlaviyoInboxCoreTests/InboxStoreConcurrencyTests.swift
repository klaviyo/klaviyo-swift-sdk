//
//  InboxStoreConcurrencyTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

/// Two independent stores on one file stand in for the app and the Notification Service Extension:
/// separate coordinators and contexts, as in two processes, sharing only the SQLite file.
final class InboxStoreConcurrencyTests: XCTestCase {
    private let company = "AbC123"
    private let ownPerWriter = 50
    private let shared = 10

    func testTwoWritersLoseNothingAndDeduplicateSharedTransmissionIDs() async throws {
        let appGroup = InboxStoreFixtures.temporaryAppGroup()
        let app = InboxStore(appGroup: appGroup, maxMessages: 1000)
        let extensionStore = InboxStore(appGroup: appGroup, maxMessages: 1000)
        let company = company
        let ownPerWriter = ownPerWriter
        let shared = shared

        let started = Date()
        let results = await withTaskGroup(of: InboxCaptureResult.self, returning: [InboxCaptureResult].self) { group in
            for (name, store) in [("app", app), ("nse", extensionStore)] {
                for index in 0..<ownPerWriter {
                    group.addTask {
                        await store.capture(InboxStoreFixtures.record(tm: "\(name)-\(index)"), companyID: company)
                    }
                }
                for index in 0..<shared {
                    group.addTask {
                        await store.capture(InboxStoreFixtures.record(tm: "shared-\(index)"), companyID: company)
                    }
                }
            }
            var all: [InboxCaptureResult] = []
            for await result in group { all.append(result) }
            return all
        }
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(results.filter { $0 == .failed }.count, 0, "no capture may fail under contention")
        XCTAssertEqual(results.filter { $0 == .captured }.count, ownPerWriter * 2 + shared)
        XCTAssertEqual(results.filter { $0 == .duplicate }.count, shared)
        XCTAssertLessThan(elapsed, 10, "contended writes must finish in bounded time")

        // A third, fresh store reads what is really on disk: every transmission ID is present.
        let reader = InboxStore(appGroup: appGroup)
        var expected = (0..<shared).map { "shared-\($0)" }
        for name in ["app", "nse"] { expected += (0..<ownPerWriter).map { "\(name)-\($0)" } }
        for id in expected {
            let stored = try await reader.message(id: id)
            XCTAssertNotNil(stored, "\(id) is missing from the store")
        }
        let extra = try await reader.message(id: "app-\(ownPerWriter)")
        XCTAssertNil(extra)
    }

    /// The first capture in each process creates the store. If the app and the extension do that at the
    /// same moment, neither may mistake the other's half-created file for a corrupt one and move it aside.
    func testConcurrentFirstOpensNeverQuarantineAHealthyStore() async {
        for run in 0..<20 {
            let appGroup = InboxStoreFixtures.temporaryAppGroup()
            let diagnostics = RecordingStoreDiagnostics()
            let app = InboxStore(appGroup: appGroup, diagnostics: diagnostics.record)
            let extensionStore = InboxStore(appGroup: appGroup, diagnostics: diagnostics.record)
            let company = company

            async let first = app.capture(InboxStoreFixtures.record(tm: "app-\(run)"), companyID: company)
            async let second = extensionStore.capture(InboxStoreFixtures.record(tm: "nse-\(run)"), companyID: company)
            let results = await [first, second]

            XCTAssertEqual(results, [.captured, .captured], "run \(run)")
            XCTAssertFalse(diagnostics.hasRecovered, "run \(run) quarantined a healthy store")
            XCTAssertFalse(diagnostics.hasDegraded, "run \(run) degraded")
        }
    }
}
