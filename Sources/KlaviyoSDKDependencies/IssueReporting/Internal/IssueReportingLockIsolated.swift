/// Adapted from Swift Issue Reporting v1.3.0 on 11/15/2024
/// https://github.com/pointfreeco/swift-issue-reporting/tree/1.3.0
/// Comments - Modified to avoid collision

import Foundation

@usableFromInline
final class IssueReportingLockIsolated<Value>: @unchecked Sendable {
  private var _value: Value
  private let lock = NSRecursiveLock()
  @usableFromInline
  init(_ value: @autoclosure @Sendable () throws -> Value) rethrows {
    self._value = try value()
  }
  @usableFromInline
  func withLock<T: Sendable>(
    _ operation: @Sendable (inout Value) throws -> T
  ) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    var value = _value
    defer { _value = value }
    return try operation(&value)
  }
}
