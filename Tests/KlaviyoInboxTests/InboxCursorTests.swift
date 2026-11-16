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

    /// A cursor made by a default query, which reads every message that is not archived.
    private func cursor(company: String? = nil, position: InboxStoreCursor? = nil) -> InboxCursor {
        InboxCursor(
            position ?? self.position,
            readFilter: .all,
            archiveFilter: .active,
            companyID: company ?? self.company
        )
    }

    private func decoded(
        _ cursor: InboxCursor,
        readFilter: InboxReadFilter = .all,
        archiveFilter: InboxArchiveFilter = .active
    ) throws -> InboxStoreCursor {
        try cursor.position(
            forCompany: company,
            readFilter: readFilter,
            archiveFilter: archiveFilter
        )
    }

    @Test
    func aCursorRoundTripsToTheStorePositionItWasMadeFrom() throws {
        let decodedPosition = try decoded(cursor())
        #expect(decodedPosition == position)
    }

    @Test
    func aCursorKeepsSubSecondSortTimes() throws {
        let precise = InboxStoreCursor(
            sortTime: InboxStoreFixtures.baseDate.addingTimeInterval(7.123),
            transmissionID: "tm-7"
        )
        let decodedPosition = try decoded(cursor(position: precise))
        #expect(decodedPosition == precise)
    }

    @Test
    func aCursorFromAnotherCompanyIsInvalid() {
        expectInvalid(cursor(company: "XyZ789"))
    }

    @Test
    func aMalformedCursorIsInvalid() {
        expectInvalid(InboxCursor(token: "not a cursor"))
    }

    @Test
    func aCursorFromAnotherVersionIsInvalid() {
        let future = Data(
            #"{"v":99,"k":"local","t":1,"i":"tm-1","c":"AbC123","r":"all","a":"active"}"#.utf8
        )
        expectInvalid(InboxCursor(token: future.base64EncodedString()))
    }

    /// Builds a cursor from raw JSON, to reach shapes `InboxCursor.init` never produces.
    private func cursor(json: String) -> InboxCursor {
        InboxCursor(token: Data(json.utf8).base64EncodedString())
    }

    private func expectInvalid(
        _ cursor: InboxCursor,
        readFilter: InboxReadFilter = .all,
        archiveFilter: InboxArchiveFilter = .active
    ) {
        var thrown: InboxError?
        do {
            _ = try cursor.position(
                forCompany: company,
                readFilter: readFilter,
                archiveFilter: archiveFilter
            )
        } catch let error as InboxError {
            thrown = error
        } catch {}
        #expect(thrown == .invalidCursor)
    }

    @Test
    func aCursorFromAnotherSourceIsInvalid() {
        expectInvalid(cursor(json: #"{"v":1,"k":"server","t":1,"i":"tm-1","c":"\#(company)","r":"all","a":"active"}"#))
    }

    @Test
    func aCursorWithNoMessageIDIsInvalid() {
        expectInvalid(cursor(json: #"{"v":1,"k":"local","t":1,"i":"","c":"\#(company)","r":"all","a":"active"}"#))
    }

    @Test
    func aCursorWithNoSortTimeIsInvalid() {
        expectInvalid(cursor(json: #"{"v":1,"k":"local","i":"tm-1","c":"\#(company)","r":"all","a":"active"}"#))
    }

    @Test
    func aTokenThatIsValidBase64ButNotJSONIsInvalid() {
        expectInvalid(cursor(json: "not json"))
    }

    @Test
    func aCursorContinuesAQueryWithTheFiltersItWasIssuedUnder() throws {
        let filtered = InboxCursor(
            position,
            readFilter: .unread,
            archiveFilter: .all,
            companyID: company
        )
        let decodedPosition = try decoded(filtered, readFilter: .unread, archiveFilter: .all)
        #expect(decodedPosition == position)
    }

    @Test
    func aCursorUnderADifferentReadFilterIsInvalid() {
        let filtered = InboxCursor(position, readFilter: .unread, archiveFilter: .active, companyID: company)
        expectInvalid(filtered, readFilter: .all, archiveFilter: .active)
        expectInvalid(filtered, readFilter: .read, archiveFilter: .active)
    }

    @Test
    func aCursorUnderADifferentArchiveFilterIsInvalid() {
        let filtered = InboxCursor(position, readFilter: .all, archiveFilter: .archived, companyID: company)
        expectInvalid(filtered, readFilter: .all, archiveFilter: .active)
        expectInvalid(filtered, readFilter: .all, archiveFilter: .all)
    }

    @Test
    func aPublicTokenRoundTripsThroughThePublicInitializer() throws {
        let original = cursor()
        let rebuilt = InboxCursor(token: original.token)
        #expect(rebuilt == original)
        let decodedPosition = try decoded(rebuilt)
        #expect(decodedPosition == position)
    }

    @Test
    func aPublicInitializerAcceptsGarbageAndTheTokenSurfacesLater() {
        // Building the cursor must not throw or crash; the token is only read when it is used.
        let garbage = InboxCursor(token: "not a cursor")
        expectInvalid(garbage)
    }
}

#endif
