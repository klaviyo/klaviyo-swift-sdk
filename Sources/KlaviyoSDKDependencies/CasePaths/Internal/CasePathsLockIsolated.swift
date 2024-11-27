/// Adapted from swift-case-paths v1.5.4 on 11/15/2024
/// https://github.com/pointfreeco/swift-case-paths/tree/1.5.4
/// Comments - renamed to avoid collision with other packages.

import Foundation

final class CasePathsLockIsolated<Value>: @unchecked Sendable {
  private var _value: Value
  private let lock = NSRecursiveLock()
  init(_ value: @autoclosure @Sendable () throws -> Value) rethrows {
    self._value = try value()
  }
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
