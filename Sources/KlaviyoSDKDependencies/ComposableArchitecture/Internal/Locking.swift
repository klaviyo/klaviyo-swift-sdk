/// Copied verbatim from TCA v1.16.1 on 11/15/2024
/// https://github.com/pointfreeco/swift-composable-architecture/tree/1.16.1

import Foundation

extension UnsafeMutablePointer<os_unfair_lock_s> {
  @inlinable @discardableResult
  func sync<R>(_ work: () -> R) -> R {
    os_unfair_lock_lock(self)
    defer { os_unfair_lock_unlock(self) }
    return work()
  }

  func lock() {
    os_unfair_lock_lock(self)
  }

  func unlock() {
    os_unfair_lock_unlock(self)
  }
}

extension NSRecursiveLock {
  @inlinable @discardableResult
  @_spi(Internals) public func sync<R>(work: () -> R) -> R {
    self.lock()
    defer { self.unlock() }
    return work()
  }
}
