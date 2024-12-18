/// Copied verbatim from TCA v1.16.1 on 11/14/2024
/// https://github.com/pointfreeco/swift-composable-architecture/tree/1.16.1

#if canImport(Combine)
  import Combine
#endif

protocol Reference<Value>: AnyObject, CustomStringConvertible, Sendable {
  associatedtype Value: Sendable
  var value: Value { get set }

  func access()
  func withMutation<T>(_ mutation: () throws -> T) rethrows -> T
  #if canImport(Combine)
    var publisher: AnyPublisher<Value, Never> { get }
  #endif
}

extension Reference {
  var valueType: Any.Type {
    Value.self
  }
}
