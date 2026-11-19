//
//  InboxCursorTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxCursorTests {
    private let company = InboxStoreFixtures.company
    private let position = InboxStoreCursor(
        sortTime: InboxStoreFixtures.baseDate.addingTimeInterval(7),
        transmissionID: "tm-7"
    )

    @Test
    func aCursorRoundTripsToTheStorePositionItWasMadeFrom() throws {
        let cursor = InboxCursor(position, companyID: company)
        let decoded = try cursor.position(forCompany: company)
        #expect(decoded == position)
    }

    @Test
    func aCursorKeepsSubSecondSortTimes() throws {
        let precise = InboxStoreCursor(
            sortTime: InboxStoreFixtures.baseDate.addingTimeInterval(7.123),
            transmissionID: "tm-7"
        )
        let decoded = try InboxCursor(precise, companyID: company).position(forCompany: company)
        #expect(decoded == precise)
    }

    @Test
    func aCursorFromAnotherCompanyIsInvalid() {
        let cursor = InboxCursor(position, companyID: "XyZ789")
        var thrown: InboxError?
        do { _ = try cursor.position(forCompany: company) } catch let error as InboxError { thrown = error } catch {}
        #expect(thrown == .invalidCursor)
    }

    @Test
    func aMalformedCursorIsInvalid() {
        var thrown: InboxError?
        do { _ = try InboxCursor(token: "not a cursor").position(forCompany: company) } catch let error as InboxError {
            thrown = error
        } catch {}
        #expect(thrown == .invalidCursor)
    }

    @Test
    func aCursorFromAnotherVersionIsInvalid() {
        let future = Data(#"{"v":99,"k":"local","t":1,"i":"tm-1","c":"AbC123"}"#.utf8)
        var thrown: InboxError?
        do {
            _ = try InboxCursor(token: future.base64EncodedString()).position(forCompany: company)
        } catch let error as InboxError {
            thrown = error
        } catch {}
        #expect(thrown == .invalidCursor)
    }

    /// Builds a cursor from raw JSON, to reach shapes `InboxCursor.init` never produces.
    private func cursor(json: String) -> InboxCursor {
        InboxCursor(token: Data(json.utf8).base64EncodedString())
    }

    private func expectInvalid(_ cursor: InboxCursor) {
        var thrown: InboxError?
        do { _ = try cursor.position(forCompany: company) } catch let error as InboxError { thrown = error } catch {}
        #expect(thrown == .invalidCursor)
    }

    @Test
    func aCursorFromAnotherSourceIsInvalid() {
        expectInvalid(cursor(json: #"{"v":1,"k":"server","t":1,"i":"tm-1","c":"\#(company)"}"#))
    }

    @Test
    func aCursorWithNoMessageIDIsInvalid() {
        expectInvalid(cursor(json: #"{"v":1,"k":"local","t":1,"i":"","c":"\#(company)"}"#))
    }

    @Test
    func aCursorWithNoSortTimeIsInvalid() {
        expectInvalid(cursor(json: #"{"v":1,"k":"local","i":"tm-1","c":"\#(company)"}"#))
    }

    @Test
    func aTokenThatIsValidBase64ButNotJSONIsInvalid() {
        expectInvalid(cursor(json: "not json"))
    }
}

#endif
