/// Copied verbatim from swift-concurrency-extras v1.2.0 on 11/15/2024
/// https://github.com/pointfreeco/swift-concurrency-extras/tree/1.2.0

import Foundation

#if !(os(iOS) || os(macOS) || os(tvOS) || os(watchOS))
  extension NSLock {
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
      self.lock()
      defer { self.unlock() }
      return try body()
    }
  }
#endif
