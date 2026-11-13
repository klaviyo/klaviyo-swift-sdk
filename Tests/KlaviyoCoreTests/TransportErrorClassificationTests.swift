@testable import KlaviyoCore
import Foundation

#if canImport(Testing)
import Testing

/// Pure-function tests only: no `environment` or `QueueStore` state, so they are safe to run in
/// parallel with other suites.
struct TransportErrorClassificationTests {
    static let retryable: [URLError.Code] = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
        .timedOut, .cannotConnectToHost, .resourceUnavailable, .cannotFindHost, .dnsLookupFailed,
        .zeroByteResource, .callIsActive, .secureConnectionFailed
    ]

    /// An unlisted code and the certificate codes all drop.
    static let dropped: [URLError.Code] = [
        .badURL, .serverCertificateUntrusted, .serverCertificateHasBadDate, .clientCertificateRejected
    ]

    @Test(arguments: retryable)
    func retryableCodes(code: URLError.Code) {
        #expect(URLError(code).transportDisposition == .retryable)
    }

    @Test(arguments: dropped)
    func otherCodesDrop(code: URLError.Code) {
        #expect(URLError(code).transportDisposition == .drop)
    }

    @Test
    func cancelledIsNotAnAttempt() {
        #expect(URLError(.cancelled).transportDisposition == .notAnAttempt)
    }
}
#endif
