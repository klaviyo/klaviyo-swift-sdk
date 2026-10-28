@testable import KlaviyoCore
import Foundation

#if canImport(Testing)
import Testing

@Suite(.serialized)
struct TransportErrorClassificationTests {
    static let retryable: [URLError.Code] = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
        .timedOut, .cannotConnectToHost, .resourceUnavailable, .cannotFindHost, .dnsLookupFailed,
        .zeroByteResource, .callIsActive, .secureConnectionFailed
    ]

    /// Certificate codes and an unlisted code both drop.
    static let dropped: [URLError.Code] = [
        .badURL, .serverCertificateUntrusted, .serverCertificateHasBadDate, .clientCertificateRejected
    ]

    init() {
        environment = KlaviyoEnvironment.test()
        SDKConfigStore.shared.reset()
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "test-api-key"))
        QueueStore.resetShared()
        QueueStore.register(makeQueueStore())
    }

    private func decision(for error: Error) -> FlushDecision {
        classifyFailure(error: .networkError(error), attemptNumber: 1)
    }

    @Test(arguments: retryable)
    func retryableCodesBackOff(code: URLError.Code) {
        #expect(decision(for: URLError(code)) == .retry(backoff: 2))
    }

    @Test(arguments: dropped)
    func otherCodesDrop(code: URLError.Code) {
        #expect(decision(for: URLError(code)) == .dequeue)
    }

    @Test
    func nonURLErrorDrops() {
        #expect(decision(for: NSError(domain: "test", code: 1)) == .dequeue)
    }

    @Test
    func cancelledIsNotAnAttempt() {
        #expect(decision(for: URLError(.cancelled)) == .abandonAttempt)
    }

    @Test
    func droppedErrorDequeuesAndNextRequestIsUntouched() async {
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "bad"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "next"), persist: .synchronous)
        let sendSpy = SendSpy(results: [.failure(.networkError(URLError(.badURL))), .success(Data())])
        let queue = RequestQueue(clock: .immediate, send: sendSpy.send)

        await queue.flushNow()

        #expect(sendSpy.sentIds == ["bad", "next"])
        #expect(sendSpy.sentAttempts == [1, 1])
        #expect(QueueStore.shared.requests.isEmpty)
    }

    @Test
    func cancelledLeavesHeadInPlaceWithNoAttempt() async {
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "head"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "tail"), persist: .synchronous)
        let sendSpy = SendSpy(results: [.failure(.networkError(URLError(.cancelled)))])
        let queue = RequestQueue(clock: .immediate, send: sendSpy.send)

        await queue.flushNow()

        #expect(sendSpy.sentIds == ["head"])
        #expect(QueueStore.shared.requests.map(\.id) == ["head", "tail"])
        #expect(QueueStore.shared.entries.map(\.attempts) == [0, 0])
        #expect(QueueStore.shared.entries.first?.nextAttemptAt == nil)
    }
}
#endif
