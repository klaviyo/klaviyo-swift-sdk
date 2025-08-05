@testable import KlaviyoCore
import XCTest

final class WithTimeoutTests: XCTestCase {
    func testWithTimeout_SuccessfulOperation() async throws {
        // Given
        let expectedResult = "success"
        let operation = {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return expectedResult
        }

        // When
        let result = try await withTimeout(seconds: 1.0, operation: operation)

        // Then
        XCTAssertEqual(result, expectedResult)
    }

    func testWithTimeout_OperationReturnsVoid() async throws {
        // Given
        var operationCompleted = false
        let operation = {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            operationCompleted = true
        }

        // When
        try await withTimeout(seconds: 1.0, operation: operation)

        // Then
        XCTAssertTrue(operationCompleted)
    }

    func testWithTimeout_OperationTimesOut() async {
        // Given
        let operation = {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            return "should not reach here"
        }

        // When/Then
        do {
            _ = try await withTimeout(seconds: 0.5, operation: operation)
            XCTFail("Expected timeout error to be thrown")
        } catch let error as TimeoutError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testWithTimeout_OperationThrowsError() async {
        // Given
        struct TestError: Error {}
        let operation = {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            throw TestError()
        }

        // When/Then
        do {
            _ = try await withTimeout(seconds: 1.0, operation: operation)
            XCTFail("Expected TestError to be thrown")
        } catch is TestError {
            // Success
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testWithTimeout_ZeroTimeout() async {
        // Given
        let operation = {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return "should not reach here"
        }

        // When/Then
        do {
            _ = try await withTimeout(seconds: 0, operation: operation)
            XCTFail("Expected timeout error to be thrown")
        } catch let error as TimeoutError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
