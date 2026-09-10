//
//  RequestQueueTestSupport.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//
//
// Shared test doubles, store factories, and request builders for `RequestQueueTests`.
// Keeping these in Support/ lets the test file contain only test methods.
//

@testable import KlaviyoCore
import Foundation
import XCTest

// MARK: - SendSpy

/// A unified configurable `send` spy that subsumes the four original inline spies:
///
/// | Old spy                  | Equivalent constructor                                    |
/// |--------------------------|-----------------------------------------------------------|
/// | `SendSpy()`              | `SendSpy()`                                               |
/// | `ScriptedSendSpy([...])`  | `SendSpy(results: [...])`                                |
/// | `ParkingSendSpy(started:)`| `SendSpy(parkFirstCall: true, started: started)`         |
/// | `FailingParkingSendSpy(started:, result: X)` | `SendSpy(results: [X, .success(Data())],  |
/// |                          |           parkFirstCall: true, started: started)`         |
///
/// Results are consumed in order; the **last** result repeats once the script is exhausted.
/// Thread-safe (`NSLock`, `@unchecked Sendable`) so it can be called from the actor under test.
final class SendSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var _results: [Result<Data, KlaviyoAPIError>]
    private var _sentIds: [String] = []
    private var _sentAttempts: [Int] = []
    private var _parked = false
    private var _resume: CheckedContinuation<Void, Never>?

    private let parkFirstCall: Bool
    private let started: XCTestExpectation?

    // MARK: - Init

    /// - Parameters:
    ///   - results: Scripted outcomes consumed in order; the last result repeats once exhausted.
    ///              Defaults to `[.success(Data())]` (always-success).
    ///   - parkFirstCall: If `true`, the first send parks on a continuation until `release()` is
    ///                    called, then returns its scripted result. Subsequent sends return their
    ///                    scripted results immediately. Defaults to `false`.
    ///   - started: Fulfilled when the first send parks. Only needed when `parkFirstCall == true`.
    init(
        results: [Result<Data, KlaviyoAPIError>] = [.success(Data())],
        parkFirstCall: Bool = false,
        started: XCTestExpectation? = nil
    ) {
        _results = results
        self.parkFirstCall = parkFirstCall
        self.started = started
    }

    // MARK: - Observables

    /// The id of every request handed to `send`, in call order.
    var sentIds: [String] { lock.lock(); defer { lock.unlock() }; return _sentIds }

    /// The `attemptNumber` from the `RequestAttemptInfo` passed with each `send` call, in order.
    var sentAttempts: [Int] { lock.lock(); defer { lock.unlock() }; return _sentAttempts }

    // MARK: - Send closure

    var send: RequestQueue.Send {
        { [self] request, info in
            let (shouldPark, result): (Bool, Result<Data, KlaviyoAPIError>) = {
                lock.lock(); defer { lock.unlock() }
                _sentIds.append(request.id)
                _sentAttempts.append(info.attemptNumber)
                let firstCall = parkFirstCall && !_parked
                if parkFirstCall { _parked = true }
                let r = _results.count > 1 ? _results.removeFirst() : (_results.first ?? .success(Data()))
                return (firstCall, r)
            }()

            if shouldPark {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    _resume = continuation
                    lock.unlock()
                    started?.fulfill()
                }
            }

            return result
        }
    }

    // MARK: - Control

    /// Resumes the parked first send so it returns its scripted result.
    func release() {
        lock.lock()
        let continuation = _resume
        _resume = nil
        lock.unlock()
        continuation?.resume()
    }
}

// MARK: - WriteSpyDiskIO

/// Records every write so `stop()`'s lease-restore behavior is observable via the shared store:
/// a `prepend` under the hood calls `save`, so a non-empty `savedBatches` after `stop()` proves a
/// restore happened (and its absence proves it did not).
final class WriteSpyDiskIO {
    private let lock = NSLock()
    private var _stored: [KlaviyoRequest] = []
    private var _savedBatches: [[KlaviyoRequest]] = []

    var stored: [KlaviyoRequest] { lock.lock(); defer { lock.unlock() }; return _stored }
    var savedBatches: [[KlaviyoRequest]] {
        lock.lock(); defer { lock.unlock() }; return _savedBatches
    }

    func makeIO() -> QueueStore.DiskIO {
        QueueStore.DiskIO(
            load: { [weak self] in self?.stored ?? [] },
            save: { [weak self] requests in
                guard let self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                self._stored = requests
                self._savedBatches.append(requests)
            }
        )
    }
}

// MARK: - Store factory

/// Creates a `QueueStore` backed by the given `WriteSpyDiskIO` (or a fresh one if omitted).
func makeQueueStore(diskIO: WriteSpyDiskIO = WriteSpyDiskIO()) -> QueueStore {
    QueueStore(
        diskIO: diskIO.makeIO(),
        scheduler: QueueStore.PersistScheduler { _, work in work() },
        emitWarning: { _ in }
    )
}

// MARK: - Request builders

/// Builds a `.registerPushToken` request whose payload carries the given token/enablement/
/// background, matching the fields `flush()` writes back to `IdentityStore` on success.
func makeRegisterPushTokenRequest(
    id: String = UUID().uuidString,
    token: String,
    enablement: PushEnablement = .authorized,
    background: PushBackground = .available
) -> KlaviyoRequest {
    let payload = PushTokenPayload(
        pushToken: token,
        enablement: enablement.rawValue,
        background: background.rawValue,
        profile: ProfilePayload(anonymousId: "anon-1")
    )
    return KlaviyoRequest(id: id, endpoint: .registerPushToken("test-api-key", payload))
}

func makeCreateProfileRequest(id: String = UUID().uuidString) -> KlaviyoRequest {
    KlaviyoRequest(
        id: id,
        endpoint: .createProfile("test-api-key", CreateProfilePayload(data: .test))
    )
}

/// A request whose endpoint has `maxRetries == 1`, so a single retry increment (count → 2)
/// exceeds the limit — letting the maxRetries-drop path be exercised in one flush.
func makeLowRetryRequest(id: String = UUID().uuidString) -> KlaviyoRequest {
    KlaviyoRequest(
        id: id,
        endpoint: .resolveDestinationURL(
            trackingLink: URL(string: "https://klaviyo.com")!,
            profileInfo: ProfilePayload(anonymousId: "anon-1")
        )
    )
}

/// Builds a 422 error-response JSON body with the given source pointer, matching the Klaviyo
/// API error envelope format that `classifyFailure` → `parseError` decodes.
func makeInvalidFieldErrorData(pointer: String) -> Data {
    """
    {
        "errors": [{
            "id": "err-1",
            "status": 422,
            "code": "invalid",
            "title": "Invalid input.",
            "detail": "Invalid value.",
            "source": { "pointer": "\(pointer)" }
        }]
    }
    """.data(using: .utf8)!
}
