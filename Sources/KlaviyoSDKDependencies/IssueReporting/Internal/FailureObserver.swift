/// Copied verbatim from Swift Issue Reporting v1.3.0 on 11/15/2024
/// https://github.com/pointfreeco/swift-issue-reporting/tree/1.3.0

import Foundation

@usableFromInline
final class FailureObserver: @unchecked Sendable {
  @TaskLocal public static var current: FailureObserver?

  private let lock = NSRecursiveLock()
  private var count = 0

  @usableFromInline
  init(count: Int = 0) {
    self.count = count
  }

  @usableFromInline
  func withLock<R>(_ body: (inout Int) -> R) -> R {
    lock.lock()
    defer { lock.unlock() }
    return body(&count)
  }
}
